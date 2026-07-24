import 'dart:typed_data';

import 'package:laconic_mysql/src/client/protocol/capabilities.dart';
import 'package:laconic_mysql/src/client/protocol/auth/handshake_packets.dart';
import 'package:test/test.dart';

void main() {
  test('plain and TLS handshakes request CLIENT_FOUND_ROWS', () {
    final initialHandshake = MysqlInitialHandshakePacket(
      protocolVersion: 10,
      serverVersion: '8.0-test',
      connectionId: 1,
      authPluginDataPart1: Uint8List(8),
      authPluginDataPart2: Uint8List(12),
      capabilityFlags:
          mysqlCapFlagClientProtocol41 |
          mysqlCapFlagClientFoundRows |
          mysqlCapFlagClientConnectWithDB |
          mysqlCapFlagClientSecureConnection |
          mysqlCapFlagClientPluginAuth |
          mysqlCapFlagClientSsl,
      charset: 45,
      statusFlags: Uint8List(2),
      authPluginName: 'mysql_native_password',
    );

    final handshake = MysqlHandshakeResponse41Packet.createWithNativePassword(
      username: 'test',
      password: 'test',
      initialHandshakePayload: initialHandshake,
    );
    final sslRequest = MysqlSslRequestPacket.createDefault(
      initialHandshakePayload: initialHandshake,
      connectWithDB: true,
    );

    expect(
      handshake.capabilityFlags & mysqlCapFlagClientFoundRows,
      mysqlCapFlagClientFoundRows,
    );
    expect(
      sslRequest.capabilityFlags & mysqlCapFlagClientFoundRows,
      mysqlCapFlagClientFoundRows,
    );
    expect(
      handshake.capabilityFlags & mysqlCapFlagClientMultiStatements,
      isZero,
    );
    expect(
      sslRequest.capabilityFlags & mysqlCapFlagClientMultiStatements,
      isZero,
    );

    final limitedServer = MysqlInitialHandshakePacket(
      protocolVersion: 10,
      serverVersion: '5.7-compatible',
      connectionId: 2,
      authPluginDataPart1: Uint8List(8),
      authPluginDataPart2: Uint8List(12),
      capabilityFlags:
          mysqlCapFlagClientProtocol41 | mysqlCapFlagClientSecureConnection,
      charset: 45,
      statusFlags: Uint8List(2),
      authPluginName: 'mysql_native_password',
    );
    final limitedHandshake =
        MysqlHandshakeResponse41Packet.createWithNativePassword(
          username: 'test',
          password: 'test',
          initialHandshakePayload: limitedServer,
        );
    expect(
      limitedHandshake.capabilityFlags & ~limitedServer.capabilityFlags,
      isZero,
    );
  });
}
