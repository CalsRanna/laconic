import 'dart:convert';
import 'dart:typed_data';

import 'package:buffer/buffer.dart';
import 'package:laconic_mysql/src/client/protocol/auth/auth_crypto.dart';
import 'package:laconic_mysql/src/client/protocol/buffer_codec.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';

class MysqlAuthSwitchRequestPacket extends MysqlPacketPayload {
  int header;
  String authPluginName;
  Uint8List authPluginData;

  MysqlAuthSwitchRequestPacket({
    required this.header,
    required this.authPluginData,
    required this.authPluginName,
  });

  factory MysqlAuthSwitchRequestPacket.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);

    int offset = 0;

    final header = byteData.getUint8(offset);
    offset += 1;

    final authPluginName = buffer.getUtf8NullTerminatedString(offset);
    offset += authPluginName.bytesRead;

    final authPluginData = Uint8List.sublistView(buffer, offset);

    return MysqlAuthSwitchRequestPacket(
      header: header,
      authPluginData: authPluginData,
      authPluginName: authPluginName.value,
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}

class MysqlAuthSwitchResponsePacket extends MysqlPacketPayload {
  Uint8List authData;

  MysqlAuthSwitchResponsePacket({required this.authData});

  factory MysqlAuthSwitchResponsePacket.createWithNativePassword({
    required String password,
    required Uint8List challenge,
  }) {
    assert(challenge.length == 20);
    final passwordBytes = utf8.encode(password);
    final authData = xor(
      sha1(passwordBytes),
      sha1(challenge + sha1(sha1(passwordBytes))),
    );
    return MysqlAuthSwitchResponsePacket(authData: authData);
  }

  factory MysqlAuthSwitchResponsePacket.createWithCachingSha2Password({
    required String password,
    required Uint8List challenge,
  }) {
    assert(challenge.length == 20);
    final passwordBytes = utf8.encode(password);
    final authData = xor(
      sha256(passwordBytes),
      sha256(sha256(sha256(passwordBytes)) + challenge),
    );
    return MysqlAuthSwitchResponsePacket(authData: authData);
  }

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);
    buffer.write(authData);
    return buffer.toBytes();
  }
}

class MysqlExtraAuthDataPacket extends MysqlPacketPayload {
  int header;
  String pluginData;

  MysqlExtraAuthDataPacket({required this.header, required this.pluginData});

  factory MysqlExtraAuthDataPacket.decode(Uint8List buffer) {
    final header = buffer[0];
    final pluginData = buffer.getUtf8StringEOF(1);
    return MysqlExtraAuthDataPacket(header: header, pluginData: pluginData);
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}

class MysqlExtraAuthDataResponsePacket extends MysqlPacketPayload {
  Uint8List data;

  MysqlExtraAuthDataResponsePacket({required this.data});

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);
    buffer.write(data);
    buffer.writeUint8(0);
    return buffer.toBytes();
  }
}
