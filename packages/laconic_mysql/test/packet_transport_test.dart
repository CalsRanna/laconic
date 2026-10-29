import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';
import 'package:laconic_mysql/src/client/transport/packet_transport.dart';
import 'package:test/test.dart';

class _InputSocket extends Stream<Uint8List> implements Socket {
  final input = StreamController<Uint8List>();
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Uint8List createFrame(int sequence, List<int> payload) => Uint8List.fromList([
    payload.length & 255,
    (payload.length >> 8) & 255,
    (payload.length >> 16) & 255,
    sequence,
    ...payload,
  ]);

  Future<List<Uint8List>> decode(
    Iterable<Uint8List> chunks, {
    int sequence = 0,
  }) async {
    final socket = _InputSocket();
    final packets = <Uint8List>[];
    final done = Completer<void>();
    final transport = MysqlPacketTransport(
      socket: socket,
      onPacket: (packet) async {
        packets.add(packet);
      },
      onError: (error, stack) {
        if (!done.isCompleted) done.completeError(error, stack);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    )..expectIncomingSequence(sequence);
    transport.start();
    // Attach an error handler before delivering socket events.
    final completed = done.future.then((_) => packets);
    for (final chunk in chunks) {
      socket.input.add(chunk);
    }
    await socket.input.close();
    return completed;
  }

  test(
    'every possible split in a header or payload reconstructs the packet',
    () async {
      final frame = createFrame(0, List.generate(20, (i) => i));
      for (var split = 1; split < frame.length; split++) {
        final decoded = await decode([
          Uint8List.sublistView(frame, 0, split),
          Uint8List.sublistView(frame, split),
        ]);
        expect(decoded.single, frame, reason: 'split=$split');
      }
    },
  );

  test(
    'single-byte fragments, empty packets and coalesced packets survive sequence wrap',
    () async {
      final frames = [
        createFrame(254, [1]),
        createFrame(255, []),
        createFrame(0, [2, 3]),
      ];
      final data = Uint8List.fromList([for (final f in frames) ...f]);
      expect(await decode([data], sequence: 254), frames);
      expect(
        await decode(
          data.map((byte) => Uint8List.fromList([byte])),
          sequence: 254,
        ),
        frames,
      );
    },
  );

  test(
    'maximum physical payload plus zero terminator produces one logical packet',
    () async {
      final data = Uint8List(MysqlPacket.maxPhysicalPayload + 8);
      data[0] = data[1] = data[2] = 255;
      data[4] = 42;
      data[MysqlPacket.maxPhysicalPayload + 3] = 24;
      data[data.length - 1] = 1;
      final chunks = <Uint8List>[];
      for (var i = 0; i < data.length; i += 16384) {
        chunks.add(
          Uint8List.sublistView(data, i, (i + 16384).clamp(0, data.length)),
        );
      }
      final packets = await decode(chunks);
      expect(packets, hasLength(1));
      expect(packets.single.length, MysqlPacket.maxPhysicalPayload + 4);
      expect(packets.single[4], 42);
      expect(packets.single.last, 24);
    },
  );

  test('a wrong response sequence still fails', () async {
    await expectLater(
      decode([
        createFrame(1, [1]),
      ]),
      throwsA(isA<MysqlProtocolException>()),
    );
  });
}
