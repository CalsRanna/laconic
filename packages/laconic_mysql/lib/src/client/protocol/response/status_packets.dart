import 'dart:typed_data';
import 'package:laconic_mysql/src/client/protocol/buffer_codec.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';

class MysqlOkPacket extends MysqlPacketPayload {
  int header;
  BigInt affectedRows;
  BigInt lastInsertId;

  MysqlOkPacket({
    required this.header,
    required this.affectedRows,
    required this.lastInsertId,
  });

  factory MysqlOkPacket.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    int offset = 0;

    final header = byteData.getUint8(offset);
    offset += 1;

    final affectedRows = byteData.getVariableEncInt(offset);
    offset += affectedRows.bytesRead;

    final lastInsertId = byteData.getVariableEncInt(offset);
    offset += lastInsertId.bytesRead;

    return MysqlOkPacket(
      header: header,
      affectedRows: affectedRows.value,
      lastInsertId: lastInsertId.value,
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}

class MysqlEofPacket extends MysqlPacketPayload {
  int header;
  int statusFlags;

  MysqlEofPacket({required this.header, required this.statusFlags});

  factory MysqlEofPacket.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    return MysqlEofPacket(
      header: byteData.getUint8(0),
      statusFlags: byteData.getUint16(3, Endian.little),
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}

class MysqlErrorPacket extends MysqlPacketPayload {
  int header;
  int errorCode;
  String errorMessage;

  MysqlErrorPacket({
    required this.header,
    required this.errorCode,
    required this.errorMessage,
  });

  factory MysqlErrorPacket.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    return MysqlErrorPacket(
      header: byteData.getUint8(0),
      errorCode: byteData.getInt2(1),
      errorMessage: buffer.getUtf8StringEOF(9),
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
