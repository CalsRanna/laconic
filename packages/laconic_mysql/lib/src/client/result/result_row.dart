import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/column_type.dart';
import 'package:laconic_mysql/src/client/protocol/response/column_packets.dart';

class MysqlResultRow {
  final List<MysqlColumnDefinitionPacket> _columns;
  final List<Object?> _values;

  MysqlResultRow({
    required List<MysqlColumnDefinitionPacket> columns,
    required List<Object?> values,
  }) : _columns = columns,
       _values = values;

  int get columnCount => _columns.length;

  Object? valueAt(int index) {
    if (index < 0 || index >= _values.length) {
      throw MysqlClientException('Column index is out of range');
    }
    return _values[index];
  }

  T? typedValueAt<T>(int index) {
    return _convertValue<T>(valueAt(index), _columns[index]);
  }

  Object? valueByName(String columnName) {
    return valueAt(_columnIndex(columnName));
  }

  T? typedValueByName<T>(String columnName) {
    final index = _columnIndex(columnName);
    return _convertValue<T>(_values[index], _columns[index]);
  }

  Map<String, Object?> toMap() {
    return {
      for (var index = 0; index < _columns.length; index++)
        _columns[index].name: _values[index],
    };
  }

  Map<String, Object?> toTypedMap() {
    return {
      for (var index = 0; index < _columns.length; index++)
        _columns[index].name: _convertToBestType(
          _values[index],
          _columns[index],
        ),
    };
  }

  int _columnIndex(String columnName) {
    final index = _columns.indexWhere(
      (column) => column.name.toLowerCase() == columnName.toLowerCase(),
    );
    if (index == -1) {
      throw MysqlClientException('There is no column with name: $columnName');
    }
    return index;
  }

  T? _convertValue<T>(Object? value, MysqlColumnDefinitionPacket column) {
    if (value == null) {
      return null;
    }
    if (T == bool &&
        value is int &&
        column.type.value == mysqlColumnTypeTiny &&
        column.columnLength == 1) {
      return (value > 0) as T;
    }
    if (T == dynamic || value is T) {
      return value as T;
    }
    if (value is! String) {
      throw MysqlProtocolException(
        'Can not convert ${value.runtimeType} to requested type $T',
      );
    }
    return column.type.convertStringValueToProvidedType<T>(
      value,
      column.columnLength,
    );
  }

  Object? _convertToBestType(
    Object? value,
    MysqlColumnDefinitionPacket column,
  ) {
    if (value == null) {
      return null;
    }
    if (value is int &&
        column.type.value == mysqlColumnTypeTiny &&
        column.columnLength == 1) {
      return value > 0;
    }
    if (value is! String) {
      return value;
    }

    final type = column.type.getBestMatchDartType(column.columnLength);
    if (type == int) return int.parse(value);
    if (type == double) return double.parse(value);
    if (type == num) return num.parse(value);
    if (type == bool) return int.parse(value) > 0;
    return value;
  }
}

class MysqlResultColumn {
  final String name;
  final MysqlColumnType type;
  final int length;

  const MysqlResultColumn({
    required this.name,
    required this.type,
    required this.length,
  });
}
