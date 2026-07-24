import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:buffer/buffer.dart';
import 'package:laconic_mysql/src/client/protocol/auth/auth_crypto.dart';
import 'package:laconic_mysql/src/client/protocol/buffer_codec.dart';
import 'package:laconic_mysql/src/client/protocol/capabilities.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';

class MysqlInitialHandshakePacket extends MysqlPacketPayload {
  int protocolVersion;
  String serverVersion;
  int connectionId;
  Uint8List authPluginDataPart1;
  int capabilityFlags;
  int charset;
  Uint8List statusFlags;
  Uint8List? authPluginDataPart2;
  String? authPluginName;

  MysqlInitialHandshakePacket({
    required this.protocolVersion,
    required this.serverVersion,
    required this.connectionId,
    required this.authPluginDataPart1,
    required this.authPluginDataPart2,
    required this.capabilityFlags,
    required this.charset,
    required this.statusFlags,
    required this.authPluginName,
  });

  factory MysqlInitialHandshakePacket.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    int offset = 0;

    // protocol version
    final protocolVersion = byteData.getUint8(offset);
    offset += 1;

    // server version
    final serverVersion = buffer.getUtf8NullTerminatedString(offset);
    offset += serverVersion.bytesRead;

    // connection id
    final connectionId = byteData.getUint32(offset, Endian.little);
    offset += 4;

    // auth-plugin-data-part-1
    final authPluginDataPart1 = Uint8List.sublistView(
      buffer,
      offset,
      offset + 8,
    );
    offset += 9; // 8 + filler;

    // capability flags (lower 2 bytes)
    final capabilitiesBytesData = ByteData(4);
    capabilitiesBytesData.setUint8(3, buffer[offset]);
    capabilitiesBytesData.setUint8(2, buffer[offset + 1]);
    offset += 2;

    // character set
    final charset = byteData.getUint8(offset);
    offset += 1;

    final statusFlags = Uint8List.sublistView(buffer, offset, offset + 2);
    offset += 2;

    // capability flags (upper 2 bytes)
    capabilitiesBytesData.setUint8(1, buffer[offset]);
    capabilitiesBytesData.setUint8(0, buffer[offset + 1]);
    offset += 2;

    final capabilityFlags = capabilitiesBytesData.getUint32(0, Endian.big);

    // length of auth-plugin-data
    int authPluginDataLength = 0;

    if (capabilityFlags & mysqlCapFlagClientPluginAuth != 0) {
      authPluginDataLength = byteData.getUint8(offset);
    }

    offset += 1;

    // reserved
    offset += 10;

    Uint8List? authPluginDataPart2;

    if (capabilityFlags & mysqlCapFlagClientSecureConnection != 0) {
      int length = max(13, authPluginDataLength - 8);

      authPluginDataPart2 = Uint8List.sublistView(
        buffer,
        offset,
        offset + length,
      );

      offset += length;
    }

    String? authPluginName;

    if (capabilityFlags & mysqlCapFlagClientPluginAuth != 0) {
      authPluginName = buffer.getUtf8NullTerminatedString(offset).value;
    }

    return MysqlInitialHandshakePacket(
      authPluginDataPart1: authPluginDataPart1,
      authPluginDataPart2: authPluginDataPart2,
      authPluginName: authPluginName,
      capabilityFlags: capabilityFlags,
      charset: charset,
      connectionId: connectionId,
      protocolVersion: protocolVersion,
      serverVersion: serverVersion.value,
      statusFlags: statusFlags,
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}

const _supportedHandshakeCapabilities =
    mysqlCapFlagClientProtocol41 |
    mysqlCapFlagClientFoundRows |
    mysqlCapFlagClientConnectWithDB |
    mysqlCapFlagClientSecureConnection |
    mysqlCapFlagClientPluginAuth |
    mysqlCapFlagClientPluginAuthLenEncClientData;

class MysqlHandshakeResponse41Packet extends MysqlPacketPayload {
  int capabilityFlags;
  int maxPacketSize;
  int characterSet;
  Uint8List authResponse;
  String authPluginName;
  String username;
  String? database;

  MysqlHandshakeResponse41Packet({
    required this.capabilityFlags,
    required this.maxPacketSize,
    required this.characterSet,
    required this.authResponse,
    required this.authPluginName,
    required this.username,
    this.database,
  });

  factory MysqlHandshakeResponse41Packet.createWithNativePassword({
    required String username,
    required String password,
    required MysqlInitialHandshakePacket initialHandshakePayload,
    bool secure = false,
  }) {
    assert(initialHandshakePayload.authPluginDataPart2 != null);
    assert(initialHandshakePayload.authPluginName != null);

    final challenge =
        initialHandshakePayload.authPluginDataPart1 +
        initialHandshakePayload.authPluginDataPart2!.sublist(0, 12);
    assert(challenge.length == 20);

    final passwordBytes = utf8.encode(password);
    final authData = xor(
      sha1(passwordBytes),
      sha1(challenge + sha1(sha1(passwordBytes))),
    );

    return MysqlHandshakeResponse41Packet(
      capabilityFlags:
          (_supportedHandshakeCapabilities |
              (secure ? mysqlCapFlagClientSsl : 0)) &
          initialHandshakePayload.capabilityFlags,
      maxPacketSize: 50 * 1024 * 1024,
      authPluginName: initialHandshakePayload.authPluginName!,
      characterSet: initialHandshakePayload.charset,
      authResponse: authData,
      username: username,
    );
  }

  factory MysqlHandshakeResponse41Packet.createWithCachingSha2Password({
    required String username,
    required String password,
    required MysqlInitialHandshakePacket initialHandshakePayload,
    bool secure = false,
  }) {
    final challenge =
        initialHandshakePayload.authPluginDataPart1 +
        initialHandshakePayload.authPluginDataPart2!.sublist(0, 12);
    assert(challenge.length == 20);

    final passwordBytes = utf8.encode(password);
    final authData = xor(
      sha256(passwordBytes),
      sha256(sha256(sha256(passwordBytes)) + challenge),
    );

    return MysqlHandshakeResponse41Packet(
      capabilityFlags:
          (_supportedHandshakeCapabilities |
              (secure ? mysqlCapFlagClientSsl : 0)) &
          initialHandshakePayload.capabilityFlags,
      maxPacketSize: 50 * 1024 * 1024,
      authPluginName: initialHandshakePayload.authPluginName!,
      characterSet: initialHandshakePayload.charset,
      authResponse: authData,
      username: username,
    );
  }

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);

    if (database == null) {
      capabilityFlags &= ~mysqlCapFlagClientConnectWithDB;
    }

    buffer.writeUint32(capabilityFlags);
    buffer.writeUint32(maxPacketSize);
    buffer.writeUint8(characterSet);
    buffer.write(List.filled(23, 0));
    buffer.write(utf8.encode(username));
    buffer.writeUint8(0);

    if (capabilityFlags & mysqlCapFlagClientSecureConnection != 0) {
      buffer.writeVariableEncInt(authResponse.lengthInBytes);
      buffer.write(authResponse);
    }

    if (database != null &&
        capabilityFlags & mysqlCapFlagClientConnectWithDB != 0) {
      buffer.write(utf8.encode(database!));
      buffer.writeUint8(0);
    }

    if (capabilityFlags & mysqlCapFlagClientPluginAuth != 0) {
      buffer.write(utf8.encode(authPluginName));
      buffer.writeUint8(0);
    }

    return buffer.toBytes();
  }
}

const _supportedSslCapabilities =
    _supportedHandshakeCapabilities | mysqlCapFlagClientSsl;

class MysqlSslRequestPacket extends MysqlPacketPayload {
  int capabilityFlags;
  int maxPacketSize;
  int characterSet;
  bool connectWithDB;

  MysqlSslRequestPacket._({
    required this.capabilityFlags,
    required this.maxPacketSize,
    required this.characterSet,
    required this.connectWithDB,
  });

  factory MysqlSslRequestPacket.createDefault({
    required MysqlInitialHandshakePacket initialHandshakePayload,
    required bool connectWithDB,
  }) {
    return MysqlSslRequestPacket._(
      capabilityFlags:
          _supportedSslCapabilities & initialHandshakePayload.capabilityFlags,
      maxPacketSize: 50 * 1024 * 1024,
      characterSet: initialHandshakePayload.charset,
      connectWithDB: connectWithDB,
    );
  }

  @override
  Uint8List encode() {
    if (!connectWithDB) {
      capabilityFlags &= ~mysqlCapFlagClientConnectWithDB;
    }

    final buffer = ByteDataWriter(endian: Endian.little);
    buffer.writeUint32(capabilityFlags);
    buffer.writeUint32(maxPacketSize);
    buffer.writeUint8(characterSet);
    buffer.write(List.filled(23, 0));
    return buffer.toBytes();
  }
}
