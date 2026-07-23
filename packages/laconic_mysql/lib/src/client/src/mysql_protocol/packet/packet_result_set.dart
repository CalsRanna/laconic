import 'dart:typed_data';
import 'package:laconic_mysql/src/client/src/mysql_protocol/mysql_packet.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_column_definition.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_result_set_row.dart';

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
