import 'dart:typed_data';
import 'package:laconic_mysql/src/client/mysql_protocol_extension.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/mysql_packet.dart';

class MySQLPacketOK extends MySQLPacketPayload {
  int header;
  BigInt affectedRows;
  BigInt lastInsertID;

  MySQLPacketOK({
    required this.header,
    required this.affectedRows,
    required this.lastInsertID,
  });

  factory MySQLPacketOK.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    int offset = 0;

    final header = byteData.getUint8(offset);
    offset += 1;

    final affectedRows = byteData.getVariableEncInt(offset);
    offset += affectedRows.bytesRead;

    final lastInsertID = byteData.getVariableEncInt(offset);
    offset += lastInsertID.bytesRead;

    return MySQLPacketOK(
      header: header,
      affectedRows: affectedRows.value,
      lastInsertID: lastInsertID.value,
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
