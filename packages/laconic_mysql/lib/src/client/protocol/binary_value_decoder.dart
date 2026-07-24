import 'dart:typed_data';

import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/buffer_codec.dart';
import 'package:laconic_mysql/src/client/protocol/column_type.dart';

DecodedValue<Object> decodeBinaryColumnValue(
  int columnType,
  ByteData data,
  Uint8List buffer,
  int startOffset, {
  bool unsigned = false,
  int charset = 0,
}) {
  switch (columnType) {
    case mysqlColumnTypeTiny:
      final value =
          unsigned ? data.getUint8(startOffset) : data.getInt8(startOffset);
      return (value: value, bytesRead: 1);
    case mysqlColumnTypeShort:
      final value =
          unsigned
              ? data.getUint16(startOffset, Endian.little)
              : data.getInt16(startOffset, Endian.little);
      return (value: value, bytesRead: 2);
    case mysqlColumnTypeLong:
    case mysqlColumnTypeInt24:
      final value =
          unsigned
              ? data.getUint32(startOffset, Endian.little)
              : data.getInt32(startOffset, Endian.little);
      return (value: value, bytesRead: 4);
    case mysqlColumnTypeLongLong:
      if (unsigned) {
        final low = data.getUint32(startOffset, Endian.little);
        final high = data.getUint32(startOffset + 4, Endian.little);
        final value = (BigInt.from(high) << 32) | BigInt.from(low);
        final maxSignedInt = BigInt.from(0x7fffffffffffffff);
        return (
          value: value <= maxSignedInt ? value.toInt() : value,
          bytesRead: 8,
        );
      }
      return (value: data.getInt64(startOffset, Endian.little), bytesRead: 8);
    case mysqlColumnTypeFloat:
      return (value: data.getFloat32(startOffset, Endian.little), bytesRead: 4);
    case mysqlColumnTypeDouble:
      return (value: data.getFloat64(startOffset, Endian.little), bytesRead: 8);
    case mysqlColumnTypeYear:
      return (value: data.getUint16(startOffset, Endian.little), bytesRead: 2);
    case mysqlColumnTypeDate:
    case mysqlColumnTypeNewDate:
    case mysqlColumnTypeDateTime:
    case mysqlColumnTypeTimestamp:
    case mysqlColumnTypeDateTime2:
    case mysqlColumnTypeTimestamp2:
      return _decodeDateTime(columnType, data, startOffset);
    case mysqlColumnTypeTime:
    case mysqlColumnTypeTime2:
      return _decodeTime(data, startOffset);
    case mysqlColumnTypeString:
    case mysqlColumnTypeVarString:
    case mysqlColumnTypeVarChar:
    case mysqlColumnTypeEnum:
    case mysqlColumnTypeSet:
    case mysqlColumnTypeLongBlob:
    case mysqlColumnTypeMediumBlob:
    case mysqlColumnTypeBlob:
    case mysqlColumnTypeTinyBlob:
      return charset == 63
          ? buffer.getLengthEncodedBytes(startOffset)
          : buffer.getUtf8LengthEncodedString(startOffset);
    case mysqlColumnTypeGeometry:
    case mysqlColumnTypeBit:
      return buffer.getLengthEncodedBytes(startOffset);
    case mysqlColumnTypeDecimal:
    case mysqlColumnTypeNewDecimal:
    case mysqlColumnTypeJson:
      return buffer.getUtf8LengthEncodedString(startOffset);
  }

  throw MysqlProtocolException(
    'Binary decoding is not implemented for column type $columnType',
  );
}

DecodedValue<String> _decodeDateTime(
  int columnType,
  ByteData data,
  int startOffset,
) {
  final initialOffset = startOffset;
  final byteCount = data.getUint8(startOffset++);
  if (byteCount == 0) {
    final isDate =
        columnType == mysqlColumnTypeDate ||
        columnType == mysqlColumnTypeNewDate;
    return (value: isDate ? '0000-00-00' : '0000-00-00 00:00:00', bytesRead: 1);
  }

  var year = 0;
  var month = 0;
  var day = 0;
  var hour = 0;
  var minute = 0;
  var second = 0;
  var microsecond = 0;

  if (byteCount >= 4) {
    year = data.getUint16(startOffset, Endian.little);
    startOffset += 2;
    month = data.getUint8(startOffset++);
    day = data.getUint8(startOffset++);
  }
  if (byteCount >= 7) {
    hour = data.getUint8(startOffset++);
    minute = data.getUint8(startOffset++);
    second = data.getUint8(startOffset++);
  }
  if (byteCount >= 11) {
    microsecond = data.getUint32(startOffset, Endian.little);
    startOffset += 4;
  }

  final result =
      StringBuffer()
        ..write('${year.toString().padLeft(4, '0')}-')
        ..write('${month.toString().padLeft(2, '0')}-')
        ..write(day.toString().padLeft(2, '0'));
  final isDate =
      columnType == mysqlColumnTypeDate || columnType == mysqlColumnTypeNewDate;
  if (!isDate) {
    result
      ..write(' ')
      ..write('${hour.toString().padLeft(2, '0')}:')
      ..write('${minute.toString().padLeft(2, '0')}:')
      ..write(second.toString().padLeft(2, '0'));
    if (microsecond != 0) {
      result.write('.${microsecond.toString().padLeft(6, '0')}');
    }
  }

  return (value: result.toString(), bytesRead: startOffset - initialOffset);
}

DecodedValue<String> _decodeTime(ByteData data, int startOffset) {
  final initialOffset = startOffset;
  final byteCount = data.getUint8(startOffset++);
  if (byteCount == 0) {
    return (value: '00:00:00', bytesRead: 1);
  }

  var negative = false;
  var days = 0;
  var hours = 0;
  var minutes = 0;
  var seconds = 0;
  var microsecond = 0;
  if (byteCount >= 8) {
    negative = data.getUint8(startOffset++) > 0;
    days = data.getUint32(startOffset, Endian.little);
    startOffset += 4;
    hours = data.getUint8(startOffset++);
    minutes = data.getUint8(startOffset++);
    seconds = data.getUint8(startOffset++);
  }
  if (byteCount >= 12) {
    microsecond = data.getUint32(startOffset, Endian.little);
    startOffset += 4;
  }

  hours += days * 24;
  final result = StringBuffer();
  if (negative) result.write('-');
  result
    ..write('${hours.toString().padLeft(2, '0')}:')
    ..write('${minutes.toString().padLeft(2, '0')}:')
    ..write(seconds.toString().padLeft(2, '0'));
  if (microsecond != 0) {
    result.write('.${microsecond.toString().padLeft(6, '0')}');
  }
  return (value: result.toString(), bytesRead: startOffset - initialOffset);
}
