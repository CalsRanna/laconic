import 'dart:typed_data';

import 'package:laconic_mysql/src/client/protocol/buffer_codec.dart';
import 'package:laconic_mysql/src/client/protocol/column_type.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';

class MysqlColumnCountPacket extends MysqlPacketPayload {
  BigInt columnCount;

  MysqlColumnCountPacket({required this.columnCount});

  factory MysqlColumnCountPacket.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    final columnCount = byteData.getVariableEncInt(0);

    return MysqlColumnCountPacket(columnCount: columnCount.value);
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}

class MysqlColumnDefinitionPacket extends MysqlPacketPayload {
  String catalog;
  String schema;
  String table;
  String orgTable;
  String name;
  String orgName;
  int charset;
  int columnLength;
  MysqlColumnType type;
  int flags;
  int decimals;

  MysqlColumnDefinitionPacket({
    required this.catalog,
    required this.schema,
    required this.table,
    required this.orgTable,
    required this.name,
    required this.orgName,
    required this.charset,
    required this.columnLength,
    required this.type,
    required this.flags,
    required this.decimals,
  });

  factory MysqlColumnDefinitionPacket.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    var offset = 0;

    final catalog = buffer.getUtf8LengthEncodedString(offset);
    offset += catalog.bytesRead;
    final schema = buffer.getUtf8LengthEncodedString(offset);
    offset += schema.bytesRead;
    final table = buffer.getUtf8LengthEncodedString(offset);
    offset += table.bytesRead;
    final orgTable = buffer.getUtf8LengthEncodedString(offset);
    offset += orgTable.bytesRead;
    final name = buffer.getUtf8LengthEncodedString(offset);
    offset += name.bytesRead;
    final orgName = buffer.getUtf8LengthEncodedString(offset);
    offset += orgName.bytesRead;
    final fixedFieldsLength = byteData.getVariableEncInt(offset);
    offset += fixedFieldsLength.bytesRead;
    final charset = byteData.getUint16(offset, Endian.little);
    offset += 2;
    final columnLength = byteData.getUint32(offset, Endian.little);
    offset += 4;
    final type = byteData.getUint8(offset);
    offset += 1;
    final flags = byteData.getUint16(offset, Endian.little);
    offset += 2;
    final decimals = byteData.getUint8(offset);

    return MysqlColumnDefinitionPacket(
      catalog: catalog.value,
      schema: schema.value,
      table: table.value,
      orgTable: orgTable.value,
      name: name.value,
      orgName: orgName.value,
      charset: charset,
      columnLength: columnLength,
      type: MysqlColumnType.create(type),
      flags: flags,
      decimals: decimals,
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
