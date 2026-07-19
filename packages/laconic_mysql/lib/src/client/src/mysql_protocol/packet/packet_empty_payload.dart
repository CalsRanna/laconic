import 'dart:typed_data';
import 'package:laconic_mysql/src/client/mysql_protocol.dart';

class MySQLPacketEmptyPayload extends MySQLPacketPayload {
  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
