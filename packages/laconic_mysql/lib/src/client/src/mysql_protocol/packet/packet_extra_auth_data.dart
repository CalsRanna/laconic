import 'dart:typed_data';
import 'package:laconic_mysql/src/client/mysql_protocol.dart';
import 'package:laconic_mysql/src/client/mysql_protocol_extension.dart';

class MySQLPacketExtraAuthData extends MySQLPacketPayload {
  int header;
  String pluginData;

  MySQLPacketExtraAuthData({
    required this.header,
    required this.pluginData,
  });

  factory MySQLPacketExtraAuthData.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    int offset = 0;

    final header = byteData.getUint8(offset);
    offset += 1;

    String pluginData = buffer.getUtf8StringEOF(offset);

    return MySQLPacketExtraAuthData(header: header, pluginData: pluginData);
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
