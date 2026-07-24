import 'dart:convert';
import 'dart:typed_data';

import 'package:buffer/buffer.dart' show ByteDataWriter;
import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/buffer_codec.dart';
import 'package:laconic_mysql/src/client/protocol/column_type.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';

class MysqlStatementPrepareCommand extends MysqlPacketPayload {
  String query;

  MysqlStatementPrepareCommand({required this.query});

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);
    buffer.writeUint8(0x16);
    buffer.write(utf8.encode(query));
    return buffer.toBytes();
  }
}

class MysqlStatementExecuteCommand extends MysqlPacketPayload {
  int statementId;
  List<dynamic> params;

  MysqlStatementExecuteCommand({
    required this.statementId,
    required this.params,
  });

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);
    buffer.writeUint8(0x17);
    buffer.writeUint32(statementId, Endian.little);
    buffer.writeUint8(0);
    buffer.writeUint32(1, Endian.little);

    if (params.isNotEmpty) {
      final nullBitmap = Uint8List(((params.length + 7) / 8).floor());
      for (var index = 0; index < params.length; index++) {
        if (params[index] == null) {
          final byteIndex = (index / 8).floor();
          final bitIndex = index % 8;
          nullBitmap[byteIndex] |= 1 << bitIndex;
        }
      }
      buffer.write(nullBitmap);
      buffer.writeUint8(1);

      for (final parameter in params) {
        buffer.writeUint8(_parameterType(parameter));
        buffer.writeUint8(0);
      }
      for (final parameter in params) {
        if (parameter != null) {
          _writeParameterValue(buffer, parameter);
        }
      }
    }

    return buffer.toBytes();
  }

  int _parameterType(Object? value) {
    if (value == null) return mysqlColumnTypeNull;
    if (value is bool) return mysqlColumnTypeTiny;
    if (value is int) return mysqlColumnTypeLongLong;
    if (value is double) return mysqlColumnTypeDouble;
    if (value is DateTime) return mysqlColumnTypeDateTime;
    if (value is Uint8List) return mysqlColumnTypeBlob;
    if (value is BigInt) return mysqlColumnTypeNewDecimal;
    if (value is String) return mysqlColumnTypeVarString;
    throw MysqlClientException(
      'Unsupported prepared-statement parameter type: ${value.runtimeType}',
    );
  }

  void _writeParameterValue(ByteDataWriter buffer, Object value) {
    if (value is bool) {
      buffer.writeUint8(value ? 1 : 0);
      return;
    }
    if (value is int) {
      buffer.writeInt64(value, Endian.little);
      return;
    }
    if (value is double) {
      buffer.writeFloat64(value, Endian.little);
      return;
    }
    if (value is DateTime) {
      final microseconds = value.millisecond * 1000 + value.microsecond;
      final hasMicroseconds = microseconds != 0;
      buffer.writeUint8(hasMicroseconds ? 11 : 7);
      buffer.writeUint16(value.year, Endian.little);
      buffer.writeUint8(value.month);
      buffer.writeUint8(value.day);
      buffer.writeUint8(value.hour);
      buffer.writeUint8(value.minute);
      buffer.writeUint8(value.second);
      if (hasMicroseconds) {
        buffer.writeUint32(microseconds, Endian.little);
      }
      return;
    }
    if (value is Uint8List) {
      buffer.writeVariableEncInt(value.lengthInBytes);
      buffer.write(value);
      return;
    }
    if (value is BigInt || value is String) {
      final encoded = utf8.encode(value.toString());
      buffer.writeVariableEncInt(encoded.length);
      buffer.write(encoded);
      return;
    }
    throw MysqlClientException(
      'Unsupported prepared-statement parameter type: ${value.runtimeType}',
    );
  }
}

class MysqlStatementCloseCommand extends MysqlPacketPayload {
  int statementId;

  MysqlStatementCloseCommand({required this.statementId});

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);
    buffer.writeUint8(0x19);
    buffer.writeUint32(statementId);
    return buffer.toBytes();
  }
}
