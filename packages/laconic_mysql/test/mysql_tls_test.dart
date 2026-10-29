import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:laconic_mysql/src/client/connection/handshake_runner.dart';
import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/auth/auth_packets.dart';
import 'package:laconic_mysql/src/client/protocol/auth/handshake_packets.dart';
import 'package:laconic_mysql/src/client/protocol/capabilities.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';
import 'package:laconic_mysql/src/client/transport/packet_transport.dart';
import 'package:test/test.dart';

class _BytesPayload extends MysqlPacketPayload {
  final Uint8List bytes;

  _BytesPayload(List<int> bytes) : bytes = Uint8List.fromList(bytes);

  @override
  Uint8List encode() => bytes;
}

class _SocketPair {
  final Socket client;
  final Socket server;

  const _SocketPair({required this.client, required this.server});

  Future<void> close() async {
    client.destroy();
    server.destroy();
  }
}

class _TlsUpgrade {
  final String host;
  final SecurityContext? context;
  final bool allowBadCertificates;

  const _TlsUpgrade({
    required this.host,
    required this.context,
    required this.allowBadCertificates,
  });
}

class _RecordingTransport extends MysqlPacketTransport {
  final List<MysqlPacket> sentPackets = [];
  final List<int> expectedSequences = [];
  final List<String> events = [];
  final List<_TlsUpgrade> upgrades = [];
  Object? upgradeError;

  _RecordingTransport(Socket socket)
    : super(
        socket: socket,
        onPacket: (_) async {},
        onError: (_, _) {},
        onDone: () {},
      );

  @override
  void sendPacket(MysqlPacket packet, {bool expectResponse = false}) {
    sentPackets.add(packet);
    events.add('send:${packet.sequenceId}');
  }

  @override
  void expectIncomingSequence(int sequence) {
    expectedSequences.add(sequence);
    events.add('expect:$sequence');
  }

  @override
  Future<void> upgradeToTls({
    required String host,
    required SecurityContext? context,
    required bool allowBadCertificates,
  }) async {
    upgrades.add(
      _TlsUpgrade(
        host: host,
        context: context,
        allowBadCertificates: allowBadCertificates,
      ),
    );
    events.add('tls');
    final error = upgradeError;
    if (error != null) {
      throw error;
    }
  }
}

void main() {
  const password = 'secret';

  Future<_SocketPair> openSocketPair() async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = listener.first;
    final client = await Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );
    final server = await accepted;
    await listener.close();
    return _SocketPair(client: client, server: server);
  }

  Uint8List initialHandshake({
    required bool supportsTls,
    String authPlugin = 'mysql_native_password',
  }) {
    final capabilities =
        MysqlCapabilities.clientProtocol41 |
        MysqlCapabilities.clientFoundRows |
        MysqlCapabilities.clientConnectWithDB |
        MysqlCapabilities.clientSecureConnection |
        MysqlCapabilities.clientPluginAuth |
        MysqlCapabilities.clientPluginAuthLenEncClientData |
        (supportsTls ? MysqlCapabilities.clientSsl : 0);
    final payload =
        BytesBuilder(copy: false)
          ..addByte(10)
          ..add(utf8.encode('8.0.36-test'))
          ..addByte(0)
          ..add([1, 0, 0, 0])
          ..add(List<int>.generate(8, (index) => index + 1))
          ..addByte(0)
          ..add([capabilities & 0xff, (capabilities >> 8) & 0xff])
          ..addByte(45)
          ..add([2, 0])
          ..add([(capabilities >> 16) & 0xff, (capabilities >> 24) & 0xff])
          ..addByte(21)
          ..add(List<int>.filled(10, 0))
          ..add(List<int>.generate(12, (index) => index + 9))
          ..addByte(0)
          ..add(utf8.encode(authPlugin))
          ..addByte(0);

    return MysqlPacket(
      sequenceId: 0,
      payload: _BytesPayload(payload.takeBytes()),
      payloadLength: 0,
    ).encode();
  }

  Uint8List extraAuthDataPacket({
    required int sequence,
    required List<int> data,
  }) {
    return MysqlPacket(
      sequenceId: sequence,
      payload: _BytesPayload([0x01, ...data]),
      payloadLength: 0,
    ).encode();
  }

  Uint8List extraAuthPacket({required int sequence, required int status}) {
    return extraAuthDataPacket(sequence: sequence, data: [status]);
  }

  String certificatePath(String name) {
    final packageRelative = 'test/certificates/$name';
    if (File(packageRelative).existsSync()) {
      return packageRelative;
    }
    return 'packages/laconic_mysql/$packageRelative';
  }

  SecurityContext serverContext() {
    return SecurityContext(withTrustedRoots: false)
      ..useCertificateChain(certificatePath('tls-server-cert.pem'))
      ..usePrivateKey(certificatePath('tls-server-key.pem'));
  }

  SecurityContext trustedClientContext() {
    return SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(certificatePath('tls-ca-cert.pem'));
  }

  Future<void> expectTlsUpgrade({
    required String host,
    required SecurityContext? context,
    required bool allowBadCertificates,
    required bool succeeds,
  }) async {
    final pair = await openSocketPair();
    final packetReceived = Completer<Uint8List>();
    final transport = MysqlPacketTransport(
      socket: pair.client,
      onPacket: (packet) async {
        if (!packetReceived.isCompleted) {
          packetReceived.complete(packet);
        }
      },
      onError: (error, stackTrace) {
        if (!packetReceived.isCompleted) {
          packetReceived.completeError(error, stackTrace);
        }
      },
      onDone: () {},
    );

    final serverUpgrade = SecureSocket.secureServer(
      pair.server,
      serverContext(),
    );
    final clientUpgrade = transport.upgradeToTls(
      host: host,
      context: context,
      allowBadCertificates: allowBadCertificates,
    );

    if (!succeeds) {
      await expectLater(
        Future.wait([serverUpgrade, clientUpgrade]),
        throwsA(isA<HandshakeException>()),
      );
      pair.client.destroy();
      pair.server.destroy();
      return;
    }

    await clientUpgrade;
    final secureServer = await serverUpgrade;
    secureServer.add([1, 0, 0, 0, 42]);
    await secureServer.flush();

    final packet = await packetReceived.future.timeout(
      const Duration(seconds: 2),
    );
    expect(packet, [1, 0, 0, 0, 42]);

    await transport.close();
    await secureServer.close();
  }

  group('TLS handshake protocol', () {
    late _SocketPair sockets;
    late _RecordingTransport transport;

    setUp(() async {
      sockets = await openSocketPair();
      transport = _RecordingTransport(sockets.client);
    });

    tearDown(() async {
      await transport.close();
      sockets.server.destroy();
    });

    test(
      'plain handshake skips SSLRequest and responds at sequence 1',
      () async {
        final runner = MysqlHandshakeRunner(
          transport: transport,
          username: 'user',
          password: password,
          host: 'db.internal',
          databaseName: 'app',
          secure: false,
          allowBadCertificates: false,
          securityContext: null,
        );

        await runner.processInitialHandshake(
          initialHandshake(supportsTls: true),
        );

        expect(transport.upgrades, isEmpty);
        expect(transport.events, ['send:1', 'expect:2']);
        expect(transport.sentPackets, hasLength(1));
        final response =
            transport.sentPackets.single.payload
                as MysqlHandshakeResponse41Packet;
        expect(response.capabilityFlags & MysqlCapabilities.clientSsl, isZero);
        expect(response.database, 'app');
      },
    );

    test('secure handshake upgrades before sending credentials', () async {
      final context = SecurityContext(withTrustedRoots: false);
      final runner = MysqlHandshakeRunner(
        transport: transport,
        username: 'user',
        password: password,
        host: 'db.internal',
        databaseName: 'app',
        secure: true,
        allowBadCertificates: true,
        securityContext: context,
      );

      await runner.processInitialHandshake(initialHandshake(supportsTls: true));

      expect(transport.events, ['send:1', 'tls', 'send:2', 'expect:3']);
      expect(transport.sentPackets, hasLength(2));
      expect(transport.sentPackets.first.payload, isA<MysqlSslRequestPacket>());
      final response =
          transport.sentPackets.last.payload as MysqlHandshakeResponse41Packet;
      expect(
        response.capabilityFlags & MysqlCapabilities.clientSsl,
        MysqlCapabilities.clientSsl,
      );
      expect(response.database, 'app');

      final upgrade = transport.upgrades.single;
      expect(upgrade.host, 'db.internal');
      expect(upgrade.context, same(context));
      expect(upgrade.allowBadCertificates, isTrue);
    });

    test('secure mode rejects a server without CLIENT_SSL', () async {
      final runner = MysqlHandshakeRunner(
        transport: transport,
        username: 'user',
        password: password,
        host: 'db.internal',
        databaseName: null,
        secure: true,
        allowBadCertificates: false,
        securityContext: null,
      );

      await expectLater(
        runner.processInitialHandshake(initialHandshake(supportsTls: false)),
        throwsA(
          isA<MysqlClientException>().having(
            (error) => error.message,
            'message',
            contains('does not support SSL'),
          ),
        ),
      );
      expect(transport.events, isEmpty);
    });

    test('TLS upgrade failure never sends the credential response', () async {
      transport.upgradeError = const HandshakeException('test TLS failure');
      final runner = MysqlHandshakeRunner(
        transport: transport,
        username: 'user',
        password: password,
        host: 'db.internal',
        databaseName: null,
        secure: true,
        allowBadCertificates: false,
        securityContext: null,
      );

      await expectLater(
        runner.processInitialHandshake(initialHandshake(supportsTls: true)),
        throwsA(isA<HandshakeException>()),
      );
      expect(transport.events, ['send:1', 'tls']);
      expect(transport.sentPackets, hasLength(1));
      expect(
        transport.sentPackets.single.payload,
        isA<MysqlSslRequestPacket>(),
      );
    });

    test(
      'full caching_sha2 authentication sends password only over TLS',
      () async {
        final runner = MysqlHandshakeRunner(
          transport: transport,
          username: 'user',
          password: password,
          host: 'db.internal',
          databaseName: null,
          secure: true,
          allowBadCertificates: false,
          securityContext: null,
        );
        await runner.processInitialHandshake(
          initialHandshake(
            supportsTls: true,
            authPlugin: 'caching_sha2_password',
          ),
        );
        transport.events.clear();
        transport.sentPackets.clear();
        transport.expectedSequences.clear();

        final authenticated = await runner.processAuthenticationResponse(
          extraAuthPacket(sequence: 3, status: 4),
        );

        expect(authenticated, isFalse);
        expect(transport.events, ['send:4', 'expect:5']);
        final response =
            transport.sentPackets.single.payload
                as MysqlExtraAuthDataResponsePacket;
        expect(response.encode(), [...utf8.encode(password), 0]);
      },
    );

    test(
      'non-TLS caching_sha2 retrieves a key and encrypts the password',
      () async {
        final runner = MysqlHandshakeRunner(
          transport: transport,
          username: 'user',
          password: password,
          host: 'db.internal',
          databaseName: null,
          secure: false,
          allowBadCertificates: false,
          securityContext: null,
        );
        await runner.processInitialHandshake(
          initialHandshake(
            supportsTls: true,
            authPlugin: 'caching_sha2_password',
          ),
        );
        transport.events.clear();
        transport.sentPackets.clear();
        transport.expectedSequences.clear();

        await runner.processAuthenticationResponse(
          extraAuthPacket(sequence: 2, status: 4),
        );
        expect(transport.events, ['send:3', 'expect:4']);
        final keyRequest =
            transport.sentPackets.single.payload
                as MysqlExtraAuthDataResponsePacket;
        expect(keyRequest.encode(), [0x02]);

        transport.events.clear();
        transport.sentPackets.clear();
        transport.expectedSequences.clear();
        final publicKey =
            File(
              certificatePath('mysql-rsa-public-key.pem'),
            ).readAsStringSync();
        await runner.processAuthenticationResponse(
          extraAuthDataPacket(sequence: 4, data: utf8.encode(publicKey)),
        );

        expect(transport.events, ['send:5', 'expect:6']);
        final encrypted =
            transport.sentPackets.single.payload
                as MysqlExtraAuthDataResponsePacket;
        expect(encrypted.appendNullTerminator, isFalse);
        expect(encrypted.encode(), hasLength(256));
        expect(encrypted.encode(), isNot(equals(utf8.encode(password))));
      },
    );

    test('non-TLS caching_sha2 can use a pinned server public key', () async {
      final publicKey =
          File(certificatePath('mysql-rsa-public-key.pem')).readAsStringSync();
      final runner = MysqlHandshakeRunner(
        transport: transport,
        username: 'user',
        password: password,
        host: 'db.internal',
        databaseName: null,
        secure: false,
        allowBadCertificates: false,
        securityContext: null,
        allowPublicKeyRetrieval: false,
        serverPublicKey: publicKey,
      );
      await runner.processInitialHandshake(
        initialHandshake(
          supportsTls: true,
          authPlugin: 'caching_sha2_password',
        ),
      );
      transport.events.clear();
      transport.sentPackets.clear();

      await runner.processAuthenticationResponse(
        extraAuthPacket(sequence: 2, status: 4),
      );

      expect(transport.events, ['send:3', 'expect:4']);
      final encrypted =
          transport.sentPackets.single.payload
              as MysqlExtraAuthDataResponsePacket;
      expect(encrypted.appendNullTerminator, isFalse);
      expect(encrypted.encode(), hasLength(256));
    });

    test('non-TLS key retrieval can be explicitly disabled', () async {
      final runner = MysqlHandshakeRunner(
        transport: transport,
        username: 'user',
        password: password,
        host: 'db.internal',
        databaseName: null,
        secure: false,
        allowBadCertificates: false,
        securityContext: null,
        allowPublicKeyRetrieval: false,
      );
      await runner.processInitialHandshake(
        initialHandshake(
          supportsTls: true,
          authPlugin: 'caching_sha2_password',
        ),
      );
      transport.events.clear();
      transport.sentPackets.clear();

      await expectLater(
        runner.processAuthenticationResponse(
          extraAuthPacket(sequence: 2, status: 4),
        ),
        throwsA(
          isA<MysqlClientException>().having(
            (error) => error.message,
            'message',
            contains('allowPublicKeyRetrieval'),
          ),
        ),
      );
      expect(transport.events, isEmpty);
      expect(transport.sentPackets, isEmpty);
    });
  });

  group('SSLRequest packet', () {
    test('contains only negotiated capabilities and is exactly 32 bytes', () {
      final initialHandshake = MysqlInitialHandshakePacket(
        protocolVersion: 10,
        serverVersion: '8.0-test',
        connectionId: 1,
        authPluginDataPart1: Uint8List(8),
        authPluginDataPart2: Uint8List(12),
        capabilityFlags:
            MysqlCapabilities.clientProtocol41 |
            MysqlCapabilities.clientFoundRows |
            MysqlCapabilities.clientConnectWithDB |
            MysqlCapabilities.clientSecureConnection |
            MysqlCapabilities.clientPluginAuth |
            MysqlCapabilities.clientSsl |
            MysqlCapabilities.clientMultiStatements,
        charset: 45,
        statusFlags: Uint8List(2),
        authPluginName: 'mysql_native_password',
      );
      final request = MysqlSslRequestPacket.createDefault(
        initialHandshakePayload: initialHandshake,
        connectWithDB: false,
      );

      final encoded = request.encode();
      final data = ByteData.sublistView(encoded);

      expect(encoded, hasLength(32));
      expect(data.getUint32(0, Endian.little), request.capabilityFlags);
      expect(request.capabilityFlags & MysqlCapabilities.clientSsl, isNot(0));
      expect(
        request.capabilityFlags & MysqlCapabilities.clientMultiStatements,
        isZero,
      );
      expect(
        request.capabilityFlags & MysqlCapabilities.clientConnectWithDB,
        isZero,
      );
      expect(data.getUint32(4, Endian.little), 50 * 1024 * 1024);
      expect(data.getUint8(8), 45);
      expect(encoded.sublist(9), everyElement(isZero));
    });
  });

  group('packet transport certificate validation', () {
    test('rejects an untrusted server certificate by default', () async {
      await expectTlsUpgrade(
        host: 'localhost',
        context: null,
        allowBadCertificates: false,
        succeeds: false,
      );
    });

    test('accepts a certificate trusted by a custom SecurityContext', () async {
      await expectTlsUpgrade(
        host: 'localhost',
        context: trustedClientContext(),
        allowBadCertificates: false,
        succeeds: true,
      );
    });

    test('still rejects a trusted certificate for the wrong host', () async {
      await expectTlsUpgrade(
        host: 'wrong.example',
        context: trustedClientContext(),
        allowBadCertificates: false,
        succeeds: false,
      );
    });

    test(
      'accepts an invalid certificate only when explicitly allowed',
      () async {
        await expectTlsUpgrade(
          host: 'localhost',
          context: null,
          allowBadCertificates: true,
          succeeds: true,
        );
      },
    );
  });
}
