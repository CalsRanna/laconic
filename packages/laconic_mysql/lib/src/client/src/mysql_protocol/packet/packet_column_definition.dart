import 'dart:typed_data';
import 'package:laconic_mysql/src/client/mysql_protocol_extension.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/mysql_column_type.dart';
import 'package:laconic_mysql/src/client/src/mysql_protocol/mysql_packet.dart';

class MySQLColumnDefinitionPacket extends MySQLPacketPayload {
  String catalog;
  String schema;
  String table;
  String orgTable;
  String name;
  String orgName;
  int charset;
  int columnLength;
  MySQLColumnType type;
  int flags;
  int decimals;

  MySQLColumnDefinitionPacket({
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

  factory MySQLColumnDefinitionPacket.decode(Uint8List buffer) {
    final byteData = ByteData.sublistView(buffer);
    int offset = 0;

    final catalog = buffer.getUtf8LengthEncodedString(offset);
    offset += catalog.item2;

    final schema = buffer.getUtf8LengthEncodedString(offset);
    offset += schema.item2;

    final table = buffer.getUtf8LengthEncodedString(offset);
    offset += table.item2;

    final orgTable = buffer.getUtf8LengthEncodedString(offset);
    offset += orgTable.item2;

    final name = buffer.getUtf8LengthEncodedString(offset);
    offset += name.item2;

    final orgName = buffer.getUtf8LengthEncodedString(offset);
    offset += orgName.item2;

    final lengthOfFixedLengthFields = byteData.getVariableEncInt(offset);
    offset += lengthOfFixedLengthFields.item2;

    final charset = byteData.getUint16(offset, Endian.little);
    offset += 2;

    final columnLength = byteData.getUint32(offset, Endian.little);
    offset += 4;

    final type = byteData.getUint8(offset);
    offset += 1;

    final flags = byteData.getUint16(offset, Endian.little);
    offset += 2;

    final decimals = byteData.getUint8(offset);

    return MySQLColumnDefinitionPacket(
      catalog: catalog.item1,
      charset: charset,
      columnLength: columnLength,
      name: name.item1,
      orgName: orgName.item1,
      orgTable: orgTable.item1,
      schema: schema.item1,
      table: table.item1,
      type: MySQLColumnType.create(type),
      flags: flags,
      decimals: decimals,
    );
  }

  @override
  Uint8List encode() {
    throw UnimplementedError();
  }
}
