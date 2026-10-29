import 'dart:typed_data';
import 'package:laconic_mysql/src/client/exceptions.dart';

abstract final class MysqlColumnFlags {
  static const unsigned = 0x0020;
}

class MysqlColumnType {
  static const decimalCode = 0x00;
  static const tinyCode = 0x01;
  static const shortCode = 0x02;
  static const longCode = 0x03;
  static const floatCode = 0x04;
  static const doubleCode = 0x05;
  static const nullCode = 0x06;
  static const timestampCode = 0x07;
  static const longLongCode = 0x08;
  static const int24Code = 0x09;
  static const dateCode = 0x0a;
  static const timeCode = 0x0b;
  static const dateTimeCode = 0x0c;
  static const yearCode = 0x0d;
  static const newDateCode = 0x0e;
  static const varCharCode = 0x0f;
  static const bitCode = 0x10;
  static const timestamp2Code = 0x11;
  static const dateTime2Code = 0x12;
  static const time2Code = 0x13;
  static const newDecimalCode = 0xf6;
  static const enumCode = 0xf7;
  static const setCode = 0xf8;
  static const tinyBlobCode = 0xf9;
  static const mediumBlobCode = 0xfa;
  static const longBlobCode = 0xfb;
  static const blobCode = 0xfc;
  static const varStringCode = 0xfd;
  static const stringCode = 0xfe;
  static const geometryCode = 0xff;
  static const jsonCode = 0xf5;

  final int _value;

  const MysqlColumnType._(int value) : _value = value;
  factory MysqlColumnType.create(int value) => MysqlColumnType._(value);
  int get value => _value;

  static const decimalType = MysqlColumnType._(decimalCode);
  static const tinyType = MysqlColumnType._(tinyCode);
  static const shortType = MysqlColumnType._(shortCode);
  static const longType = MysqlColumnType._(longCode);
  static const floatType = MysqlColumnType._(floatCode);
  static const doubleType = MysqlColumnType._(doubleCode);
  static const nullType = MysqlColumnType._(nullCode);
  static const timestampType = MysqlColumnType._(timestampCode);
  static const longLongType = MysqlColumnType._(longLongCode);
  static const int24Type = MysqlColumnType._(int24Code);
  static const dateType = MysqlColumnType._(dateCode);
  static const timeType = MysqlColumnType._(timeCode);
  static const dateTimeType = MysqlColumnType._(dateTimeCode);
  static const yearType = MysqlColumnType._(yearCode);
  static const newDateType = MysqlColumnType._(newDateCode);
  static const varCharType = MysqlColumnType._(varCharCode);
  static const bitType = MysqlColumnType._(bitCode);
  static const timestamp2Type = MysqlColumnType._(timestamp2Code);
  static const dateTime2Type = MysqlColumnType._(dateTime2Code);
  static const time2Type = MysqlColumnType._(time2Code);
  static const newDecimalType = MysqlColumnType._(newDecimalCode);
  static const enumType = MysqlColumnType._(enumCode);
  static const setType = MysqlColumnType._(setCode);
  static const tinyBlobType = MysqlColumnType._(tinyBlobCode);
  static const mediumBlobType = MysqlColumnType._(mediumBlobCode);
  static const longBlobType = MysqlColumnType._(longBlobCode);
  static const blobType = MysqlColumnType._(blobCode);
  static const varStringType = MysqlColumnType._(varStringCode);
  static const stringType = MysqlColumnType._(stringCode);
  static const geometryType = MysqlColumnType._(geometryCode);

  T? convertStringValueToProvidedType<T>(String? value, [int? columnLength]) {
    if (value == null) {
      return null;
    }

    if (T == String || T == dynamic) {
      return value as T;
    }

    if (T == bool) {
      if (_value == tinyCode && columnLength == 1) {
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
        case tinyCode:
        case shortCode:
        case longCode:
        case longLongCode:
        case int24Code:
        case yearCode:
          return int.parse(value) as T;
        default:
          throw MysqlProtocolException(
            "Can not convert MySQL type $_value to requested type int",
          );
      }
    }

    if (T == double) {
      switch (_value) {
        case tinyCode:
        case shortCode:
        case longCode:
        case longLongCode:
        case int24Code:
        case floatCode:
        case doubleCode:
          return double.parse(value) as T;
        default:
          throw MysqlProtocolException(
            "Can not convert MySQL type $_value to requested type double",
          );
      }
    }

    if (T == num) {
      switch (_value) {
        case tinyCode:
        case shortCode:
        case longCode:
        case longLongCode:
        case int24Code:
        case floatCode:
        case doubleCode:
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
      case stringCode:
      case varStringCode:
      case varCharCode:
      case enumCode:
      case setCode:
      case decimalCode:
      case newDecimalCode:
      case jsonCode:
        return String;
      case longBlobCode:
      case mediumBlobCode:
      case blobCode:
      case tinyBlobCode:
      case geometryCode:
      case bitCode:
        return Uint8List;
      case tinyCode:
        if (columnLength == 1) {
          return bool;
        } else {
          return int;
        }
      case shortCode:
      case longCode:
      case longLongCode:
      case int24Code:
      case yearCode:
        return int;
      case floatCode:
      case doubleCode:
        return double;
      default:
        return String;
    }
  }
}
