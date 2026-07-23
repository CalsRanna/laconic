import 'dart:typed_data';
import 'package:laconic_mysql/src/client/mysql_protocol.dart';
import 'package:laconic_mysql/src/client/mysql_protocol_extension.dart';
import 'package:tuple/tuple.dart';

class MySQLResultSetRowPacket extends MySQLPacketPayload {
  List<Object?> values;

  MySQLResultSetRowPacket({required this.values});

  factory MySQLResultSetRowPacket.decode(
    Uint8List buffer,
    List<MySQLColumnDefinitionPacket> colDefs,
  ) {
    final byteData = ByteData.sublistView(buffer);
    int offset = 0;

    List<Object?> values = [];

    for (int x = 0; x < colDefs.length; x++) {
      Tuple2<Object, int> value;
      final nextByte = byteData.getUint8(offset);

      if (nextByte == 0xfb) {
        values.add(null);
        offset += 1;
      } else {
        final colDef = colDefs[x];
        final type = colDef.type.intVal;
        final isBinaryString =
            colDef.charset == 63 &&
            (type == mysqlColumnTypeString ||
                type == mysqlColumnTypeVarString ||
                type == mysqlColumnTypeVarChar);
        final isBinaryBlob =
            colDef.charset == 63 &&
            (type == mysqlColumnTypeTinyBlob ||
                type == mysqlColumnTypeMediumBlob ||
                type == mysqlColumnTypeLongBlob ||
                type == mysqlColumnTypeBlob);
        final isBinary =
            isBinaryString ||
            isBinaryBlob ||
            type == mysqlColumnTypeGeometry ||
            type == mysqlColumnTypeBit;
        value =
            isBinary
                ? buffer.getLengthEncodedBytes(offset)
                : buffer.getUtf8LengthEncodedString(offset);
        values.add(value.item1);
        offset += value.item2;
      }
    }

    return MySQLResultSetRowPacket(values: values);
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
