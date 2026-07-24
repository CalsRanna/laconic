import 'dart:typed_data';
import 'package:laconic_mysql/src/client/protocol/packet.dart';

class MysqlStatementPrepareOkPacket extends MysqlPacketPayload {
  int header;
  int statementId;
  int columnCount;
  int parameterCount;
  int warningCount;

  MysqlStatementPrepareOkPacket({
    required this.header,
    required this.statementId,
    required this.columnCount,
    required this.parameterCount,
    required this.warningCount,
  });

  factory MysqlStatementPrepareOkPacket.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    int offset = 0;

    final header = byteData.getUint8(offset);
    offset += 1;

    final statementID = byteData.getUint32(offset, Endian.little);
    offset += 4;

    final numColumns = byteData.getUint16(offset, Endian.little);
    offset += 2;

    final numParams = byteData.getUint16(offset, Endian.little);
    offset += 2;

    // filler
    offset += 1;

    final numWarnings = byteData.getUint16(offset, Endian.little);
    offset += 2;

    return MysqlStatementPrepareOkPacket(
      header: header,
      statementId: statementID,
      columnCount: numColumns,
      parameterCount: numParams,
      warningCount: numWarnings,
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
