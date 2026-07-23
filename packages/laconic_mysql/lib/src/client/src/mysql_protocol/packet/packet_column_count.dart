import 'dart:typed_data';

import 'package:laconic_mysql/src/client/mysql_protocol_extension.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/mysql_packet.dart';

class MySQLPacketColumnCount extends MySQLPacketPayload {
  BigInt columnCount;

  MySQLPacketColumnCount({required this.columnCount});

  factory MySQLPacketColumnCount.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    final columnCount = byteData.getVariableEncInt(0);

    return MySQLPacketColumnCount(columnCount: columnCount.item1);
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
