import 'dart:typed_data';

import 'package:buffer/buffer.dart' show ByteDataWriter;

const mysqlMaxPhysicalPacketPayload = 0x00ffffff;

typedef MysqlPacketHeader = ({int payloadLength, int sequenceId});

abstract class MysqlPacketPayload {
  Uint8List encode();
}

class MysqlPacket {
  int sequenceId;
  int payloadLength;
  MysqlPacketPayload payload;

  MysqlPacket({
    required this.sequenceId,
    required this.payload,
    required this.payloadLength,
  });

  static int getPacketLength(Uint8List buffer) {
    final data =
        ByteData(4)
          ..setUint8(0, buffer[0])
          ..setUint8(1, buffer[1])
          ..setUint8(2, buffer[2])
          ..setUint8(3, 0);

    return data.getUint32(0, Endian.little) + 4;
  }

  static MysqlPacketHeader decodePacketHeader(Uint8List buffer) {
    final data =
        ByteData(4)
          ..setUint8(0, buffer[0])
          ..setUint8(1, buffer[1])
          ..setUint8(2, buffer[2])
          ..setUint8(3, 0);

    return (
      payloadLength: data.getUint32(0, Endian.little),
      sequenceId: buffer[3],
    );
  }

  Uint8List encode() {
    final payloadData = payload.encode();
    final buffer = ByteDataWriter(endian: Endian.little);

    var offset = 0;
    var currentSequence = sequenceId & 0xff;
    while (offset < payloadData.lengthInBytes) {
      final remaining = payloadData.lengthInBytes - offset;
      final chunkLength =
          remaining > mysqlMaxPhysicalPacketPayload
              ? mysqlMaxPhysicalPacketPayload
              : remaining;

      buffer.writeUint8(chunkLength & 0xff);
      buffer.writeUint8((chunkLength >> 8) & 0xff);
      buffer.writeUint8((chunkLength >> 16) & 0xff);
      buffer.writeUint8(currentSequence);
      if (chunkLength > 0) {
        buffer.write(
          Uint8List.sublistView(payloadData, offset, offset + chunkLength),
        );
      }

      offset += chunkLength;
      currentSequence = (currentSequence + 1) & 0xff;
    }

    if (payloadData.isEmpty ||
        payloadData.lengthInBytes % mysqlMaxPhysicalPacketPayload == 0) {
      buffer.writeUint8(0);
      buffer.writeUint8(0);
      buffer.writeUint8(0);
      buffer.writeUint8(currentSequence);
    }

    return buffer.toBytes();
  }
}
