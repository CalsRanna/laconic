import 'dart:convert';
import 'dart:typed_data';

import 'package:buffer/buffer.dart' show ByteDataWriter;
import 'package:laconic_mysql/src/client/protocol/packet.dart';

class MysqlQueryCommand extends MysqlPacketPayload {
  String query;

  MysqlQueryCommand({required this.query});

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);
    buffer.writeUint8(3);
    buffer.write(utf8.encode(query));
    return buffer.toBytes();
  }
}

class MysqlQuitCommand extends MysqlPacketPayload {
  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);
    buffer.writeUint8(1);
    return buffer.toBytes();
  }
}
