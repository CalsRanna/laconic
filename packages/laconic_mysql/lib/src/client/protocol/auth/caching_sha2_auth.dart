import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'auth_crypto.dart';

class _RsaPublicKey {
  final BigInt modulus;
  final BigInt exponent;

  const _RsaPublicKey(this.modulus, this.exponent);

  int get modulusLength => (modulus.bitLength + 7) ~/ 8;
}

class _DerObject {
  final int tag;
  final Uint8List value;
  final int endOffset;

  const _DerObject(this.tag, this.value, this.endOffset);
}

class _DerLength {
  final int valueOffset;
  final int valueLength;

  const _DerLength(this.valueOffset, this.valueLength);
}

abstract final class MysqlCachingSha2Auth {
  static const _sha1Length = 20;

  /// Builds the caching_sha2_password request for the server RSA public key.
  static Uint8List publicKeyRequest() => Uint8List.fromList([0x02]);

  /// Encrypts a caching_sha2_password password for a non-TLS connection.
  ///
  /// MySQL requires the NUL-terminated password to be XORed with the handshake
  /// nonce before RSA-OAEP encryption using SHA-1.
  static Uint8List encryptPassword(
    String password,
    Uint8List nonce,
    String publicKeyPem,
  ) {
    if (nonce.isEmpty) {
      throw ArgumentError.value(nonce, 'nonce', 'must not be empty');
    }

    final publicKey = _parseRsaPublicKey(publicKeyPem);
    final scrambledPassword = _scramblePassword(password, nonce);
    final encoded = _oaepEncode(scrambledPassword, publicKey.modulusLength);
    final encrypted = _bytesToBigInt(
      encoded,
    ).modPow(publicKey.exponent, publicKey.modulus);
    return _bigIntToBytes(encrypted, publicKey.modulusLength);
  }

  static Uint8List _scramblePassword(String password, Uint8List nonce) {
    final passwordBytes = utf8.encode(password);
    final scrambled = Uint8List(passwordBytes.length + 1)
      ..setRange(0, passwordBytes.length, passwordBytes);

    for (var index = 0; index < scrambled.length; index++) {
      scrambled[index] ^= nonce[index % nonce.length];
    }
    return scrambled;
  }

  static Uint8List _oaepEncode(Uint8List message, int modulusLength) {
    if (message.length > modulusLength - 2 * _sha1Length - 2) {
      throw ArgumentError.value(
        message.length,
        'password',
        'is too long for the server RSA key',
      );
    }

    final paddingLength = modulusLength - message.length - 2 * _sha1Length - 2;
    final dataBlock = Uint8List.fromList([
      ...MysqlAuthCrypto.sha1(const []),
      ...List<int>.filled(paddingLength, 0),
      0x01,
      ...message,
    ]);
    final seed = _secureRandomBytes(_sha1Length);
    final maskedDataBlock = _xorEqualLength(
      dataBlock,
      _mgf1(seed, dataBlock.length),
    );
    final maskedSeed = _xorEqualLength(
      seed,
      _mgf1(maskedDataBlock, _sha1Length),
    );

    return Uint8List.fromList([0, ...maskedSeed, ...maskedDataBlock]);
  }

  static Uint8List _mgf1(Uint8List seed, int outputLength) {
    final output = BytesBuilder(copy: false);
    var counter = 0;
    while (output.length < outputLength) {
      final counterBytes = Uint8List(4);
      ByteData.sublistView(counterBytes).setUint32(0, counter, Endian.big);
      output.add(MysqlAuthCrypto.sha1([...seed, ...counterBytes]));
      counter++;
    }
    return Uint8List.sublistView(output.takeBytes(), 0, outputLength);
  }

  static Uint8List _xorEqualLength(Uint8List left, Uint8List right) {
    final result = Uint8List(left.length);
    for (var index = 0; index < left.length; index++) {
      result[index] = left[index] ^ right[index];
    }
    return result;
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static _RsaPublicKey _parseRsaPublicKey(String pem) {
    final body = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll('-----BEGIN RSA PUBLIC KEY-----', '')
        .replaceAll('-----END RSA PUBLIC KEY-----', '')
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'\s'), '');

    final Uint8List der;
    try {
      der = base64.decode(body);
    } on FormatException catch (error) {
      throw ArgumentError.value(
        pem,
        'publicKeyPem',
        'is not a valid PEM public key: $error',
      );
    }

    final root = _readDerObject(der, 0);
    if (root.tag != 0x30 || root.endOffset != der.length) {
      throw ArgumentError.value(
        pem,
        'publicKeyPem',
        'must contain one DER sequence',
      );
    }

    final rootChildren = _readDerChildren(root.value);
    if (_looksLikePkcs1(rootChildren)) {
      return _rsaKeyFromIntegers(rootChildren);
    }

    final bitString =
        rootChildren.where((child) => child.tag == 0x03).firstOrNull;
    if (bitString == null ||
        bitString.value.isEmpty ||
        bitString.value.first != 0) {
      throw ArgumentError.value(
        pem,
        'publicKeyPem',
        'is not an RSA SubjectPublicKeyInfo key',
      );
    }

    final keySequence = _readDerObject(
      Uint8List.sublistView(bitString.value, 1),
      0,
    );
    if (keySequence.tag != 0x30 ||
        keySequence.endOffset != bitString.value.length - 1) {
      throw ArgumentError.value(
        pem,
        'publicKeyPem',
        'contains an invalid RSA key payload',
      );
    }
    return _rsaKeyFromIntegers(_readDerChildren(keySequence.value));
  }

  static bool _looksLikePkcs1(List<_DerObject> objects) {
    return objects.length == 2 &&
        objects[0].tag == 0x02 &&
        objects[1].tag == 0x02;
  }

  static _RsaPublicKey _rsaKeyFromIntegers(List<_DerObject> objects) {
    if (!_looksLikePkcs1(objects)) {
      throw ArgumentError('RSA public key must contain modulus and exponent');
    }

    final modulus = _unsignedDerInteger(objects[0].value);
    final exponent = _unsignedDerInteger(objects[1].value);
    if (modulus <= BigInt.zero || exponent <= BigInt.one) {
      throw ArgumentError('RSA public key contains invalid parameters');
    }
    return _RsaPublicKey(modulus, exponent);
  }

  static List<_DerObject> _readDerChildren(Uint8List bytes) {
    final result = <_DerObject>[];
    var offset = 0;
    while (offset < bytes.length) {
      final object = _readDerObject(bytes, offset);
      result.add(object);
      offset = object.endOffset;
    }
    return result;
  }

  static _DerObject _readDerObject(Uint8List bytes, int offset) {
    if (offset < 0 || offset >= bytes.length) {
      throw ArgumentError('Unexpected end of DER data');
    }

    final tag = bytes[offset];
    final length = _readDerLength(bytes, offset + 1);
    final endOffset = length.valueOffset + length.valueLength;
    if (endOffset > bytes.length) {
      throw ArgumentError('DER object length exceeds the available data');
    }
    return _DerObject(
      tag,
      Uint8List.sublistView(bytes, length.valueOffset, endOffset),
      endOffset,
    );
  }

  static _DerLength _readDerLength(Uint8List bytes, int offset) {
    if (offset >= bytes.length) {
      throw ArgumentError('Missing DER object length');
    }

    final first = bytes[offset];
    if (first < 0x80) {
      return _DerLength(offset + 1, first);
    }

    final byteCount = first & 0x7f;
    if (byteCount == 0 || byteCount > 4 || offset + byteCount >= bytes.length) {
      throw ArgumentError('Unsupported DER length encoding');
    }

    var length = 0;
    for (var index = 0; index < byteCount; index++) {
      length = (length << 8) | bytes[offset + index + 1];
    }
    return _DerLength(offset + byteCount + 1, length);
  }

  static BigInt _unsignedDerInteger(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw ArgumentError('DER integer must not be empty');
    }
    final unsigned = bytes.first == 0 ? Uint8List.sublistView(bytes, 1) : bytes;
    return _bytesToBigInt(unsigned);
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final result = Uint8List(length);
    var remaining = value;
    for (var index = length - 1; index >= 0; index--) {
      result[index] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    return result;
  }
}
