import 'dart:typed_data';
import 'package:laconic_mysql/src/client/exceptions.dart';

const mysqlColumnTypeDecimal = 0x00;
const mysqlColumnTypeTiny = 0x01;
const mysqlColumnTypeShort = 0x02;
const mysqlColumnTypeLong = 0x03;
const mysqlColumnTypeFloat = 0x04;
const mysqlColumnTypeDouble = 0x05;
const mysqlColumnTypeNull = 0x06;
const mysqlColumnTypeTimestamp = 0x07;
const mysqlColumnTypeLongLong = 0x08;
const mysqlColumnTypeInt24 = 0x09;
const mysqlColumnTypeDate = 0x0a;
const mysqlColumnTypeTime = 0x0b;
const mysqlColumnTypeDateTime = 0x0c;
const mysqlColumnTypeYear = 0x0d;
const mysqlColumnTypeNewDate = 0x0e;
const mysqlColumnTypeVarChar = 0x0f;
const mysqlColumnTypeBit = 0x10;
const mysqlColumnTypeTimestamp2 = 0x11;
const mysqlColumnTypeDateTime2 = 0x12;
const mysqlColumnTypeTime2 = 0x13;
const mysqlColumnTypeNewDecimal = 0xf6;
const mysqlColumnTypeEnum = 0xf7;
const mysqlColumnTypeSet = 0xf8;
const mysqlColumnTypeTinyBlob = 0xf9;
const mysqlColumnTypeMediumBlob = 0xfa;
const mysqlColumnTypeLongBlob = 0xfb;
const mysqlColumnTypeBlob = 0xfc;
const mysqlColumnTypeVarString = 0xfd;
const mysqlColumnTypeString = 0xfe;
const mysqlColumnTypeGeometry = 0xff;
const mysqlColumnTypeJson = 0xf5;

const mysqlColumnFlagUnsigned = 0x0020;

class MysqlColumnType {
  final int _value;

  const MysqlColumnType._(int value) : _value = value;
  factory MysqlColumnType.create(int value) => MysqlColumnType._(value);
  int get value => _value;

  static const decimalType = MysqlColumnType._(mysqlColumnTypeDecimal);
  static const tinyType = MysqlColumnType._(mysqlColumnTypeTiny);
  static const shortType = MysqlColumnType._(mysqlColumnTypeShort);
  static const longType = MysqlColumnType._(mysqlColumnTypeLong);
  static const floatType = MysqlColumnType._(mysqlColumnTypeFloat);
  static const doubleType = MysqlColumnType._(mysqlColumnTypeDouble);
  static const nullType = MysqlColumnType._(mysqlColumnTypeNull);
  static const timestampType = MysqlColumnType._(mysqlColumnTypeTimestamp);
  static const longLongType = MysqlColumnType._(mysqlColumnTypeLongLong);
  static const int24Type = MysqlColumnType._(mysqlColumnTypeInt24);
  static const dateType = MysqlColumnType._(mysqlColumnTypeDate);
  static const timeType = MysqlColumnType._(mysqlColumnTypeTime);
  static const dateTimeType = MysqlColumnType._(mysqlColumnTypeDateTime);
  static const yearType = MysqlColumnType._(mysqlColumnTypeYear);
  static const newDateType = MysqlColumnType._(mysqlColumnTypeNewDate);
  static const varCharType = MysqlColumnType._(mysqlColumnTypeVarChar);
  static const bitType = MysqlColumnType._(mysqlColumnTypeBit);
  static const timestamp2Type = MysqlColumnType._(mysqlColumnTypeTimestamp2);
  static const dateTime2Type = MysqlColumnType._(mysqlColumnTypeDateTime2);
  static const time2Type = MysqlColumnType._(mysqlColumnTypeTime2);
  static const newDecimalType = MysqlColumnType._(mysqlColumnTypeNewDecimal);
  static const enumType = MysqlColumnType._(mysqlColumnTypeEnum);
  static const setType = MysqlColumnType._(mysqlColumnTypeSet);
  static const tinyBlobType = MysqlColumnType._(mysqlColumnTypeTinyBlob);
  static const mediumBlobType = MysqlColumnType._(mysqlColumnTypeMediumBlob);
  static const longBlobType = MysqlColumnType._(mysqlColumnTypeLongBlob);
  static const blobType = MysqlColumnType._(mysqlColumnTypeBlob);
  static const varStringType = MysqlColumnType._(mysqlColumnTypeVarString);
  static const stringType = MysqlColumnType._(mysqlColumnTypeString);
  static const geometryType = MysqlColumnType._(mysqlColumnTypeGeometry);

  T? convertStringValueToProvidedType<T>(String? value, [int? columnLength]) {
    if (value == null) {
      return null;
    }

    if (T == String || T == dynamic) {
      return value as T;
    }

    if (T == bool) {
      if (_value == mysqlColumnTypeTiny && columnLength == 1) {
        return int.parse(value) > 0 as T;
      } else {
        throw MysqlProtocolException(
          "Can not convert MySQL type $_value to requested type bool",
        );
      }
    }

    // convert to int
    if (T == int) {
      switch (_value) {
        // types convertible to dart int
        case mysqlColumnTypeTiny:
        case mysqlColumnTypeShort:
        case mysqlColumnTypeLong:
        case mysqlColumnTypeLongLong:
        case mysqlColumnTypeInt24:
        case mysqlColumnTypeYear:
          return int.parse(value) as T;
        default:
          throw MysqlProtocolException(
            "Can not convert MySQL type $_value to requested type int",
          );
      }
    }

    if (T == double) {
      switch (_value) {
        case mysqlColumnTypeTiny:
        case mysqlColumnTypeShort:
        case mysqlColumnTypeLong:
        case mysqlColumnTypeLongLong:
        case mysqlColumnTypeInt24:
        case mysqlColumnTypeFloat:
        case mysqlColumnTypeDouble:
          return double.parse(value) as T;
        default:
          throw MysqlProtocolException(
            "Can not convert MySQL type $_value to requested type double",
          );
      }
    }

    if (T == num) {
      switch (_value) {
        case mysqlColumnTypeTiny:
        case mysqlColumnTypeShort:
        case mysqlColumnTypeLong:
        case mysqlColumnTypeLongLong:
        case mysqlColumnTypeInt24:
        case mysqlColumnTypeFloat:
        case mysqlColumnTypeDouble:
          return num.parse(value) as T;
        default:
          throw MysqlProtocolException(
            "Can not convert MySQL type $_value to requested type num",
          );
      }
    }

    throw MysqlProtocolException(
      "Can not convert MySQL type ${T.runtimeType} to requested type int",
    );
  }

  Type getBestMatchDartType(int columnLength) {
    switch (_value) {
      case mysqlColumnTypeString:
      case mysqlColumnTypeVarString:
      case mysqlColumnTypeVarChar:
      case mysqlColumnTypeEnum:
      case mysqlColumnTypeSet:
      case mysqlColumnTypeDecimal:
      case mysqlColumnTypeNewDecimal:
      case mysqlColumnTypeJson:
        return String;
      case mysqlColumnTypeLongBlob:
      case mysqlColumnTypeMediumBlob:
      case mysqlColumnTypeBlob:
      case mysqlColumnTypeTinyBlob:
      case mysqlColumnTypeGeometry:
      case mysqlColumnTypeBit:
        return Uint8List;
      case mysqlColumnTypeTiny:
        if (columnLength == 1) {
          return bool;
        } else {
          return int;
        }
      case mysqlColumnTypeShort:
      case mysqlColumnTypeLong:
      case mysqlColumnTypeLongLong:
      case mysqlColumnTypeInt24:
      case mysqlColumnTypeYear:
        return int;
      case mysqlColumnTypeFloat:
      case mysqlColumnTypeDouble:
        return double;
      default:
        return String;
    }
  }
}
