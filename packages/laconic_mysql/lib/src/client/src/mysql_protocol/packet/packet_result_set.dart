import 'dart:typed_data';
import 'package:laconic_mysql/src/client/mysql_protocol.dart';

class MySQLPacketResultSet extends MySQLPacketPayload {
  BigInt columnCount;
  List<MySQLColumnDefinitionPacket> columns;
  List<MySQLResultSetRowPacket> rows;

  MySQLPacketResultSet({
    required this.columnCount,
    required this.columns,
    required this.rows,
  });

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
