import 'dart:async';

import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/response/column_packets.dart';
import 'package:laconic_mysql/src/client/protocol/response/status_packets.dart';
import 'package:laconic_mysql/src/client/result/result_row.dart';

abstract class MysqlResultSet {
  int get columnCount;

  int get rowCount;

  BigInt get affectedRows;

  BigInt get lastInsertId;

  MysqlResultSet? next;

  Iterable<MysqlResultRow> get rows;

  Iterable<MysqlResultColumn> get columns;

  Stream<MysqlResultRow> get rowStream => Stream.fromIterable(rows);
}

class MysqlBufferedResultSet extends MysqlResultSet {
  final List<MysqlColumnDefinitionPacket> _columns;
  final List<List<Object?>> _rowValues;

  MysqlBufferedResultSet({
    required List<MysqlColumnDefinitionPacket> columns,
    required List<List<Object?>> rows,
  }) : _columns = columns,
       _rowValues = rows;

  @override
  int get columnCount => _columns.length;

  @override
  int get rowCount => _rowValues.length;

  @override
  BigInt get affectedRows => BigInt.zero;

  @override
  BigInt get lastInsertId => BigInt.zero;

  @override
  Iterable<MysqlResultRow> get rows sync* {
    for (final values in _rowValues) {
      yield MysqlResultRow(columns: _columns, values: values);
    }
  }

  @override
  Iterable<MysqlResultColumn> get columns => _columns.map(_toResultColumn);
}

class MysqlStreamingResultSet extends MysqlResultSet {
  final List<MysqlColumnDefinitionPacket> _columns;
  late final StreamController<MysqlResultRow> _controller;
  bool _cancelled = false;

  MysqlStreamingResultSet({
    required List<MysqlColumnDefinitionPacket> columns,
    required void Function() onPause,
    required void Function() onResume,
    required void Function() onCancel,
  }) : _columns = columns {
    _controller = StreamController(
      onPause: onPause,
      onResume: onResume,
      onCancel: () {
        _cancelled = true;
        onCancel();
      },
    );
  }

  bool get isCancelled => _cancelled;

  StreamSink<MysqlResultRow> get sink => _controller.sink;

  @override
  int get columnCount => _columns.length;

  @override
  int get rowCount =>
      throw MysqlClientException(
        'rowCount is unavailable for a streaming result set',
      );

  @override
  BigInt get affectedRows => BigInt.zero;

  @override
  BigInt get lastInsertId => BigInt.zero;

  @override
  Iterable<MysqlResultRow> get rows =>
      throw MysqlClientException('Use rowStream for a streaming result set');

  @override
  Stream<MysqlResultRow> get rowStream => _controller.stream;

  @override
  Iterable<MysqlResultColumn> get columns => _columns.map(_toResultColumn);
}

class MysqlCommandResult extends MysqlResultSet {
  final MysqlOkPacket _okPacket;

  MysqlCommandResult(MysqlOkPacket okPacket) : _okPacket = okPacket;

  @override
  int get columnCount => 0;

  @override
  int get rowCount => 0;

  @override
  BigInt get affectedRows => _okPacket.affectedRows;

  @override
  BigInt get lastInsertId => _okPacket.lastInsertId;

  @override
  Iterable<MysqlResultRow> get rows => const [];

  @override
  Iterable<MysqlResultColumn> get columns => const [];
}

MysqlResultColumn _toResultColumn(MysqlColumnDefinitionPacket column) {
  return MysqlResultColumn(
    name: column.name,
    type: column.type,
    length: column.columnLength,
  );
}
