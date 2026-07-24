import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/auth/auth_packets.dart';
import 'package:laconic_mysql/src/client/protocol/auth/handshake_packets.dart';
import 'package:laconic_mysql/src/client/protocol/capabilities.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';
import 'package:laconic_mysql/src/client/protocol/packet_decoder.dart';
import 'package:laconic_mysql/src/client/protocol/response/status_packets.dart';
import 'package:laconic_mysql/src/client/transport/packet_transport.dart';

class MysqlHandshakeRunner {
  final MysqlPacketTransport _transport;
  final String _username;
  final String _password;
  final String _host;
  final String? _databaseName;
  final bool _secure;
  final bool _allowBadCertificates;
  final SecurityContext? _securityContext;

  int _serverCapabilities = 0;
  String? _activeAuthPluginName;

  MysqlHandshakeRunner({
    required MysqlPacketTransport transport,
    required String username,
    required String password,
    required String host,
    required String? databaseName,
    required bool secure,
    required bool allowBadCertificates,
    required SecurityContext? securityContext,
  }) : _transport = transport,
       _username = username,
       _password = password,
       _host = host,
       _databaseName = databaseName,
       _secure = secure,
       _allowBadCertificates = allowBadCertificates,
       _securityContext = securityContext;

  Future<void> processInitialHandshake(Uint8List data) async {
    if (MysqlPacketDecoder.detectPacketType(data) ==
        MysqlGenericPacketType.error) {
      final packet = MysqlPacketDecoder.decodeGeneric(data);
      final payload = packet.payload as MysqlErrorPacket;
      throw MysqlServerException(payload.errorMessage, payload.errorCode);
    }

    final packet = MysqlPacketDecoder.decodeInitialHandshake(data);
    final payload = packet.payload;
    if (payload is! MysqlInitialHandshakePacket) {
      throw const MysqlClientException('Expected an initial handshake packet');
    }

    _serverCapabilities = payload.capabilityFlags;
    if (_secure && (_serverCapabilities & mysqlCapFlagClientSsl == 0)) {
      throw const MysqlClientException(
        'Server does not support SSL. Disable secure mode explicitly or '
        'enable SSL on the server.',
      );
    }

    if (_secure) {
      final sslRequest = MysqlPacket(
        sequenceId: 1,
        payload: MysqlSslRequestPacket.createDefault(
          initialHandshakePayload: payload,
          connectWithDB: _databaseName != null,
        ),
        payloadLength: 0,
      );
      _transport.sendPacket(sslRequest);
      await _transport.upgradeToTls(
        host: _host,
        context: _securityContext,
        allowBadCertificates: _allowBadCertificates,
      );
    }

    _activeAuthPluginName = payload.authPluginName;
    final MysqlHandshakeResponse41Packet response;
    switch (payload.authPluginName) {
      case 'mysql_native_password':
        response = MysqlHandshakeResponse41Packet.createWithNativePassword(
          username: _username,
          password: _password,
          initialHandshakePayload: payload,
          secure: _secure,
        );
      case 'caching_sha2_password':
        response = MysqlHandshakeResponse41Packet.createWithCachingSha2Password(
          username: _username,
          password: _password,
          initialHandshakePayload: payload,
          secure: _secure,
        );
      default:
        throw MysqlClientException(
          'Unsupported auth plugin: ${payload.authPluginName}',
        );
    }

    response.database = _databaseName;
    final responsePacket = MysqlPacket(
      payload: response,
      sequenceId: _secure ? 2 : 1,
      payloadLength: 0,
    );
    _transport.sendPacket(responsePacket);
    _transport.expectIncomingSequence(responsePacket.sequenceId + 1);
  }

  Future<bool> processAuthenticationResponse(Uint8List data) async {
    if (data[4] == 0xfe) {
      final packet = MysqlPacketDecoder.decodeAuthSwitchRequest(data);
      final payload = packet.payload as MysqlAuthSwitchRequestPacket;
      _activeAuthPluginName = payload.authPluginName;

      final MysqlAuthSwitchResponsePacket response;
      switch (payload.authPluginName) {
        case 'mysql_native_password':
          response = MysqlAuthSwitchResponsePacket.createWithNativePassword(
            password: _password,
            challenge: payload.authPluginData.sublist(0, 20),
          );
        case 'caching_sha2_password':
          response =
              MysqlAuthSwitchResponsePacket.createWithCachingSha2Password(
                password: _password,
                challenge: payload.authPluginData.sublist(0, 20),
              );
        default:
          throw MysqlClientException(
            'Unsupported auth plugin: ${payload.authPluginName}',
          );
      }

      final responsePacket = MysqlPacket(
        sequenceId: packet.sequenceId + 1,
        payload: response,
        payloadLength: 0,
      );
      _transport.sendPacket(responsePacket);
      _transport.expectIncomingSequence(responsePacket.sequenceId + 1);
      return false;
    }

    final packet = MysqlPacketDecoder.decodeGeneric(data);
    final payload = packet.payload;
    if (payload is MysqlExtraAuthDataPacket) {
      if (_activeAuthPluginName != 'caching_sha2_password') {
        throw MysqlClientException(
          'Unexpected extra auth data for plugin $_activeAuthPluginName',
        );
      }
      if (!_secure) {
        throw const MysqlClientException(
          'caching_sha2_password full authentication requires TLS',
        );
      }

      final status = payload.pluginData.codeUnitAt(0);
      if (status == 3) {
        return false;
      }
      if (status == 4) {
        final responsePacket = MysqlPacket(
          sequenceId: packet.sequenceId + 1,
          payload: MysqlExtraAuthDataResponsePacket(
            data: Uint8List.fromList(utf8.encode(_password)),
          ),
          payloadLength: 0,
        );
        _transport.sendPacket(responsePacket);
        _transport.expectIncomingSequence(responsePacket.sequenceId + 1);
        return false;
      }
      throw MysqlClientException('Unsupported extra auth data: $data');
    }

    if (packet.isError) {
      final error = payload as MysqlErrorPacket;
      throw MysqlServerException(error.errorMessage, error.errorCode);
    }
    return packet.isOk;
  }
}
