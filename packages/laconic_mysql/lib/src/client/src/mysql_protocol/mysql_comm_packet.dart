import 'dart:convert';
import 'dart:typed_data';
import 'package:buffer/buffer.dart' show ByteDataWriter;
import 'package:laconic_mysql/src/client/exception.dart';
import 'package:laconic_mysql/src/client/mysql_protocol.dart';
import 'package:laconic_mysql/src/client/mysql_protocol_extension.dart';

class MySQLPacketCommInitDB extends MySQLPacketPayload {
  String schemaName;

  MySQLPacketCommInitDB({required this.schemaName});

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);

    // command type
    buffer.writeUint8(2);
    buffer.write(utf8.encode(schemaName));

    return buffer.toBytes();
  }
}

class MySQLPacketCommQuery extends MySQLPacketPayload {
  String query;

  MySQLPacketCommQuery({required this.query});

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);

    // command type
    buffer.writeUint8(3);
    buffer.write(utf8.encode(query));

    return buffer.toBytes();
  }
}

class MySQLPacketCommStmtPrepare extends MySQLPacketPayload {
  String query;

  MySQLPacketCommStmtPrepare({required this.query});

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);

    // command type
    buffer.writeUint8(0x16);
    buffer.write(utf8.encode(query));

    return buffer.toBytes();
  }
}

class MySQLPacketCommStmtExecute extends MySQLPacketPayload {
  int stmtID;
  List<dynamic> params; // (type, value)

  MySQLPacketCommStmtExecute({required this.stmtID, required this.params});

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);

    // command type
    buffer.writeUint8(0x17);
    // stmt id
    buffer.writeUint32(stmtID, Endian.little);
    // flags
    buffer.writeUint8(0);
    // iteration count (always 1)
    buffer.writeUint32(1, Endian.little);

    // params
    if (params.isNotEmpty) {
      // create null-bitmap
      final bitmapSize = ((params.length + 7) / 8).floor();
      final nullBitmap = Uint8List(bitmapSize);

      // write null values into null bitmap
      int paramIndex = 0;
      for (final param in params) {
        if (param == null) {
          final paramByteIndex = ((paramIndex) / 8).floor();
          final paramBitIndex = ((paramIndex) % 8);
          nullBitmap[paramByteIndex] =
              nullBitmap[paramByteIndex] | (1 << paramBitIndex);
        }
        paramIndex++;
      }

      // write null bitmap
      buffer.write(nullBitmap);

      // write new-param-bound flag
      buffer.writeUint8(1);

      // write not null values

      // write param types
      for (final param in params) {
        buffer.writeUint8(_parameterType(param));
        // All integer values are encoded as signed Dart ints.
        buffer.writeUint8(0);
      }
      // write param values
      for (final param in params) {
        if (param != null) {
          _writeParameterValue(buffer, param);
        }
      }
    }

    return buffer.toBytes();
  }

  int _parameterType(Object? value) {
    if (value == null) {
      return mysqlColumnTypeNull;
    }
    if (value is bool) {
      return mysqlColumnTypeTiny;
    }
    if (value is int) {
      return mysqlColumnTypeLongLong;
    }
    if (value is double) {
      return mysqlColumnTypeDouble;
    }
    if (value is DateTime) {
      return mysqlColumnTypeDateTime;
    }
    if (value is Uint8List) {
      return mysqlColumnTypeBlob;
    }
    if (value is BigInt) {
      return mysqlColumnTypeNewDecimal;
    }
    if (value is String) {
      return mysqlColumnTypeVarString;
    }
    throw MySQLClientException(
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
      final encodedData = utf8.encode(value.toString());
      buffer.writeVariableEncInt(encodedData.length);
      buffer.write(encodedData);
      return;
    }

    throw MySQLClientException(
      'Unsupported prepared-statement parameter type: ${value.runtimeType}',
    );
  }
}

class MySQLPacketCommQuit extends MySQLPacketPayload {
  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);

    // command type
    buffer.writeUint8(1);

    return buffer.toBytes();
  }
}

class MySQLPacketCommStmtClose extends MySQLPacketPayload {
  int stmtID;

  MySQLPacketCommStmtClose({required this.stmtID});

  @override
  Uint8List encode() {
    final buffer = ByteDataWriter(endian: Endian.little);

    // command type
    buffer.writeUint8(0x19);
    buffer.writeUint32(stmtID);

    return buffer.toBytes();
  }
}
