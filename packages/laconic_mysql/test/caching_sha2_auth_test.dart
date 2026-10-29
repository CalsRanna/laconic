import 'dart:io';
import 'dart:typed_data';

import 'package:laconic_mysql/src/client/protocol/auth/caching_sha2_auth.dart';
import 'package:test/test.dart';

void main() {
  String fixturePath(String name) {
    final packageRelative = 'test/certificates/$name';
    if (File(packageRelative).existsSync()) {
      return packageRelative;
    }
    return 'packages/laconic_mysql/$packageRelative';
  }

  group('caching_sha2_password RSA authentication', () {
    late String publicKey;
    final nonce = Uint8List.fromList(List<int>.generate(20, (index) => index));

    setUpAll(() {
      publicKey =
          File(fixturePath('mysql-rsa-public-key.pem')).readAsStringSync();
    });

    test('builds the MySQL server public-key request', () {
      expect(MysqlCachingSha2Auth.publicKeyRequest(), [0x02]);
    });

    test('encrypts the scrambled password to the RSA modulus length', () {
      final first = MysqlCachingSha2Auth.encryptPassword(
        'secret',
        nonce,
        publicKey,
      );
      final second = MysqlCachingSha2Auth.encryptPassword(
        'secret',
        nonce,
        publicKey,
      );

      expect(first, hasLength(256));
      expect(second, hasLength(256));
      expect(first, isNot(equals(second)));
      expect(first, isNot(containsAllInOrder('secret'.codeUnits)));
    });

    test('accepts a NUL terminator after a server PEM key', () {
      final encrypted = MysqlCachingSha2Auth.encryptPassword(
        'secret',
        nonce,
        '$publicKey\u0000',
      );

      expect(encrypted, hasLength(256));
    });

    test('rejects an empty handshake nonce', () {
      expect(
        () => MysqlCachingSha2Auth.encryptPassword(
          'secret',
          Uint8List(0),
          publicKey,
        ),
        throwsArgumentError,
      );
    });

    test('rejects malformed public keys', () {
      expect(
        () => MysqlCachingSha2Auth.encryptPassword(
          'secret',
          nonce,
          'not a public key',
        ),
        throwsArgumentError,
      );
    });

    test('rejects passwords too long for the RSA key', () {
      expect(
        () => MysqlCachingSha2Auth.encryptPassword(
          List.filled(214, 'x').join(),
          nonce,
          publicKey,
        ),
        throwsArgumentError,
      );
    });
  });
}
