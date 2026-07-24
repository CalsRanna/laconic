import 'dart:typed_data';
import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/binary_value_decoder.dart';
import 'package:laconic_mysql/src/client/protocol/buffer_codec.dart';
import 'package:laconic_mysql/src/client/protocol/column_type.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';
import 'package:laconic_mysql/src/client/protocol/response/column_packets.dart';

class MysqlTextRowPacket extends MysqlPacketPayload {
  List<Object?> values;

  MysqlTextRowPacket({required this.values});

  factory MysqlTextRowPacket.decode(
    Uint8List buffer,
    List<MysqlColumnDefinitionPacket> colDefs,
  ) {
    final byteData = ByteData.sublistView(buffer);
    int offset = 0;

    List<Object?> values = [];

    for (int x = 0; x < colDefs.length; x++) {
      DecodedValue<Object> value;
      final nextByte = byteData.getUint8(offset);

      if (nextByte == 0xfb) {
        values.add(null);
        offset += 1;
      } else {
        final colDef = colDefs[x];
        final type = colDef.type.value;
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
        values.add(value.value);
        offset += value.bytesRead;
      }
    }

    return MysqlTextRowPacket(values: values);
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}

class MysqlBinaryRowPacket extends MysqlPacketPayload {
  List<Object?> values;

  MysqlBinaryRowPacket({required this.values});

  factory MysqlBinaryRowPacket.decode(
    Uint8List buffer,
    List<MysqlColumnDefinitionPacket> colDefs,
  ) {
    final byteData = ByteData.sublistView(buffer);
    var offset = 0;

    final type = byteData.getUint8(offset);
    offset += 1;
    if (type != 0) {
      throw MysqlProtocolException(
        'Can not decode MysqlBinaryRowPacket: '
        'packet type is not 0x00',
      );
    }

    final values = <Object?>[];
    final nullBitmapSize = ((colDefs.length + 9) / 8).floor();
    final nullBitmap = Uint8List.sublistView(
      buffer,
      offset,
      offset + nullBitmapSize,
    );
    offset += nullBitmapSize;

    for (var index = 0; index < colDefs.length; index++) {
      final bitmapByteIndex = ((index + 2) / 8).floor();
      final bitmapBitIndex = (index + 2) % 8;
      final isNull = nullBitmap[bitmapByteIndex] & (1 << bitmapBitIndex) != 0;

      if (isNull) {
        values.add(null);
        continue;
      }

      final column = colDefs[index];
      final parsed = decodeBinaryColumnValue(
        column.type.value,
        byteData,
        buffer,
        offset,
        unsigned: column.flags & mysqlColumnFlagUnsigned != 0,
        charset: column.charset,
      );
      offset += parsed.bytesRead;
      values.add(parsed.value);
    }

    return MysqlBinaryRowPacket(values: values);
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
