import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';

class MysqlPacketTransport {
  Socket _socket;
  final Future<void> Function(Uint8List packet) _onPacket;
  final void Function(Object error, StackTrace stackTrace) _onError;
  final void Function() _onDone;

  StreamSubscription<Uint8List>? _subscription;
  Future<void> _processing = Future.value();
  final List<int> _incompleteData = [];
  final BytesBuilder _logicalPacketData = BytesBuilder(copy: false);
  int? _logicalPacketSequence;
  int? _expectedIncomingSequence;
  bool _pausedForBackpressure = false;

  MysqlPacketTransport({
    required Socket socket,
    required Future<void> Function(Uint8List packet) onPacket,
    required void Function(Object error, StackTrace stackTrace) onError,
    required void Function() onDone,
  }) : _socket = socket,
       _onPacket = onPacket,
       _onError = onError,
       _onDone = onDone;

  void start() {
    _subscription = _socket.listen(
      (data) {
        _processing = _processing
            .then((_) async {
              for (final packet in _splitPackets(data)) {
                await _onPacket(packet);
              }
            })
            .catchError((Object error, StackTrace stackTrace) async {
              _onError(error, stackTrace);
            });
      },
      onError: _onError,
      onDone: () {
        unawaited(_processing.whenComplete(_onDone));
      },
      cancelOnError: false,
    );
  }

  Future<void> upgradeToTls({
    required String host,
    required SecurityContext? context,
    required bool allowBadCertificates,
  }) async {
    _subscription?.pause();
    _socket = await SecureSocket.secure(
      _socket,
      host: host,
      context: context,
      onBadCertificate: allowBadCertificates ? (certificate) => true : null,
    );
    start();
  }

  void sendPacket(MysqlPacket packet, {bool expectResponse = false}) {
    final encoded = packet.encode();
    if (expectResponse) {
      var offset = 0;
      var nextSequence = packet.sequenceId & 0xff;
      while (offset < encoded.lengthInBytes) {
        final frame = Uint8List.sublistView(encoded, offset);
        final header = MysqlPacket.decodePacketHeader(frame);
        nextSequence = (header.sequenceId + 1) & 0xff;
        offset += header.payloadLength + 4;
      }
      expectIncomingSequence(nextSequence);
    }
    _socket.add(encoded);
  }

  void expectIncomingSequence(int sequence) {
    _expectedIncomingSequence = sequence & 0xff;
  }

  void pause() {
    if (_pausedForBackpressure) {
      return;
    }
    _pausedForBackpressure = true;
    _subscription?.pause();
  }

  void resume() {
    if (!_pausedForBackpressure) {
      return;
    }
    _pausedForBackpressure = false;
    final subscription = _subscription;
    if (subscription != null && subscription.isPaused) {
      subscription.resume();
    }
  }

  Future<void> flush() => _socket.flush();

  Future<void> close() async {
    await _subscription?.cancel();
    await _socket.close();
  }

  void destroy() {
    unawaited(_subscription?.cancel() ?? Future.value());
    _socket.destroy();
  }

  void reset() {
    _incompleteData.clear();
    _logicalPacketData.takeBytes();
    _logicalPacketSequence = null;
    _expectedIncomingSequence = null;
    _pausedForBackpressure = false;
  }

  Iterable<Uint8List> _splitPackets(Uint8List data) sync* {
    if (_incompleteData.isNotEmpty) {
      data = Uint8List.fromList(_incompleteData + data.toList());
      _incompleteData.clear();
    }

    var view = data;
    while (true) {
      if (view.length < 4) {
        _incompleteData.addAll(view);
        break;
      }

      final packetLength = MysqlPacket.getPacketLength(view);
      if (view.lengthInBytes < packetLength) {
        _incompleteData.addAll(view);
        break;
      }

      final chunk = Uint8List.sublistView(view, 0, packetLength);
      final header = MysqlPacket.decodePacketHeader(chunk);
      final expectedSequence = _expectedIncomingSequence;
      if (expectedSequence != null && header.sequenceId != expectedSequence) {
        throw MysqlProtocolException(
          'Unexpected packet sequence id ${header.sequenceId}; '
          'expected $expectedSequence',
        );
      }
      _expectedIncomingSequence = (header.sequenceId + 1) & 0xff;

      _logicalPacketSequence ??= header.sequenceId;
      if (header.payloadLength > 0) {
        _logicalPacketData.add(Uint8List.sublistView(chunk, 4));
      }

      if (header.payloadLength < mysqlMaxPhysicalPacketPayload) {
        final payload = _logicalPacketData.takeBytes();
        final logicalPacket = Uint8List(4 + payload.lengthInBytes);
        final advertisedLength =
            payload.lengthInBytes > mysqlMaxPhysicalPacketPayload
                ? mysqlMaxPhysicalPacketPayload
                : payload.lengthInBytes;
        logicalPacket[0] = advertisedLength & 0xff;
        logicalPacket[1] = (advertisedLength >> 8) & 0xff;
        logicalPacket[2] = (advertisedLength >> 16) & 0xff;
        logicalPacket[3] = _logicalPacketSequence!;
        logicalPacket.setRange(4, logicalPacket.length, payload);
        _logicalPacketSequence = null;
        yield logicalPacket;
      }

      view = Uint8List.sublistView(view, packetLength);
      if (view.isEmpty) {
        break;
      }
    }
  }
}
