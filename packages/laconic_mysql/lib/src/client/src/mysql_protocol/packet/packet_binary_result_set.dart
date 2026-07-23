import 'dart:typed_data';
import 'package:laconic_mysql/src/client/src/mysql_protocol/mysql_packet.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_binary_result_set_row.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/packet/packet_column_definition.dart';

class MySQLPacketBinaryResultSet extends MySQLPacketPayload {
  BigInt columnCount;
  List<MySQLColumnDefinitionPacket> columns;
  List<MySQLBinaryResultSetRowPacket> rows;

  MySQLPacketBinaryResultSet({
    required this.columnCount,
    required this.columns,
    required this.rows,
  });

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
