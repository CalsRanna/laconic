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
  final Uint8List _partialHeader = Uint8List(4);
  int _headerLength = 0;
  Uint8List? _partialPacket;
  int _packetOffset = 0;
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
    _headerLength = 0;
    _partialPacket = null;
    _packetOffset = 0;
    _logicalPacketData.takeBytes();
    _logicalPacketSequence = null;
    _expectedIncomingSequence = null;
    _pausedForBackpressure = false;
  }

  Iterable<Uint8List> _physicalPackets(Uint8List data) sync* {
    var offset = 0;
    while (offset < data.length) {
      var packet = _partialPacket;
      if (packet == null) {
        // Complete packets can be decoded directly from the socket buffer.
        if (_headerLength == 0 && data.length - offset >= 4) {
          final view = Uint8List.sublistView(data, offset);
          final length = MysqlPacket.getPacketLength(view);
          if (view.length >= length) {
            offset += length;
            yield Uint8List.sublistView(view, 0, length);
            continue;
          }
        }
        final count = (4 - _headerLength).clamp(0, data.length - offset);
        _partialHeader.setRange(
          _headerLength,
          _headerLength + count,
          data,
          offset,
        );
        _headerLength += count;
        offset += count;
        if (_headerLength < 4) return;
        packet = Uint8List(MysqlPacket.getPacketLength(_partialHeader));
        packet.setRange(0, 4, _partialHeader);
        _partialPacket = packet;
        _packetOffset = 4;
        _headerLength = 0;
      }
      final count = (packet.length - _packetOffset).clamp(
        0,
        data.length - offset,
      );
      packet.setRange(_packetOffset, _packetOffset + count, data, offset);
      _packetOffset += count;
      offset += count;
      if (_packetOffset == packet.length) {
        _partialPacket = null;
        _packetOffset = 0;
        yield packet;
      }
    }
  }

  Iterable<Uint8List> _splitPackets(Uint8List data) sync* {
    for (final chunk in _physicalPackets(data)) {
      final header = MysqlPacket.decodePacketHeader(chunk);
      final expectedSequence = _expectedIncomingSequence;
      if (expectedSequence != null && header.sequenceId != expectedSequence) {
        throw MysqlProtocolException(
          'Unexpected packet sequence id ${header.sequenceId}; '
          'expected $expectedSequence',
        );
      }
      _expectedIncomingSequence = (header.sequenceId + 1) & 0xff;
      if (_logicalPacketSequence == null &&
          header.payloadLength < MysqlPacket.maxPhysicalPayload) {
        yield chunk;
        continue;
      }
      _logicalPacketSequence ??= header.sequenceId;
      if (header.payloadLength > 0) {
        _logicalPacketData.add(Uint8List.sublistView(chunk, 4));
      }
      if (header.payloadLength < MysqlPacket.maxPhysicalPayload) {
        final payload = _logicalPacketData.takeBytes();
        final logicalPacket = Uint8List(4 + payload.length);
        final length = payload.length.clamp(0, MysqlPacket.maxPhysicalPayload);
        logicalPacket[0] = length & 0xff;
        logicalPacket[1] = (length >> 8) & 0xff;
        logicalPacket[2] = (length >> 16) & 0xff;
        logicalPacket[3] = _logicalPacketSequence!;
        logicalPacket.setRange(4, logicalPacket.length, payload);
        _logicalPacketSequence = null;
        yield logicalPacket;
      }
    }
  }
}
