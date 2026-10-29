import 'dart:async';

import 'package:laconic/laconic.dart';

/// A simple SqlGrammar implementation for testing core package functionality.
class MockGrammar extends SqlGrammar {
  @override
  CompiledQuery compileSelect({
    required String table,
    required List<Object> columns,
    required List<Map<String, dynamic>> wheres,
    required List<Map<String, dynamic>> joins,
    required List<Map<String, dynamic>> orders,
    required List<Object> groups,
    required List<Map<String, dynamic>> havings,
    required bool distinct,
    int? limit,
    int? offset,
    List<Map<String, dynamic>> locks = const [],
    List<Object?> selectBindings = const [],
    List<Object?> groupBindings = const [],
    List<String>? distinctColumns,
    CompiledQuery? fromSubquery,
    String? fromAlias,
    List<Map<String, String>> indexHints = const [],
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('select ');
    if (distinct) buffer.write('distinct ');
    buffer.write(
      columns.isEmpty || (columns.length == 1 && columns[0] == '*')
          ? '*'
          : columns.join(', '),
    );
    bindings.addAll(selectBindings);
    buffer.write(' from $table');

    if (joins.isNotEmpty) {
      for (final join in joins) {
        final type = join['type'] as String? ?? 'inner';
        final joinTable = join['table'] as String;
        final conditions = join['conditions'] as List<Map<String, dynamic>>;
        if (type == 'left') {
          buffer.write(' left join $joinTable');
        } else if (type == 'cross') {
          buffer.write(' cross join $joinTable');
        } else {
          buffer.write(' join $joinTable');
        }
        if (conditions.isNotEmpty) {
          buffer.write(' on ');
          for (var i = 0; i < conditions.length; i++) {
            final c = conditions[i];
            if (i > 0) buffer.write(' ${c['boolean']} ');
            buffer.write('${c['left']} ${c['comparator']} ${c['right']}');
          }
        }
      }
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      for (var i = 0; i < wheres.length; i++) {
        final w = wheres[i];
        if (i > 0) buffer.write(' ${w['boolean']} ');
        final type = w['type'];
        if (type == 'basic') {
          final value = w['value'];
          if (value is Expression) {
            buffer.write('${w['column']} ${w['comparator']} ${value.sql}');
          } else {
            buffer.write('${w['column']} ${w['comparator']} ?');
            bindings.add(value);
          }
        } else if (type == 'in') {
          final values = w['values'] as List<Object?>;
          final not = w['not'] as bool;
          if (values.isEmpty) {
            buffer.write(not ? '1 = 1' : '1 = 0');
          } else {
            final placeholders = List.filled(values.length, '?').join(', ');
            buffer.write(
              '${w['column']} ${not ? 'not in' : 'in'} ($placeholders)',
            );
            bindings.addAll(values);
          }
        } else if (type == 'null') {
          final not = w['not'] as bool;
          buffer.write('${w['column']} ${not ? 'is not null' : 'is null'}');
        } else if (type == 'raw') {
          buffer.write('(${w['sql']})');
          bindings.addAll(w['bindings'] as List<Object?>);
        }
      }
    }

    if (orders.isNotEmpty) {
      buffer.write(' order by ');
      final orderParts = <String>[];
      for (final o in orders) {
        if (o['type'] == 'raw') {
          orderParts.add(o['sql'] as String);
          bindings.addAll(o['bindings'] as List<Object?>);
        } else {
          orderParts.add('${o['column']} ${o['direction']}');
        }
      }
      buffer.write(orderParts.join(', '));
    }

    if (limit != null) {
      buffer.write(' limit ?');
      bindings.add(limit);
    }

    if (offset != null) {
      buffer.write(' offset ?');
      bindings.add(offset);
    }

    for (final lock in locks) {
      if (lock['type'] == 'for_update') {
        buffer.write(' for update');
      } else if (lock['type'] == 'raw') {
        buffer.write(' ${lock['value']}');
      }
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileInsert({
    required String table,
    required List<Map<String, Object?>> data,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];
    final columns = data.first.keys.toList();

    buffer.write('insert into $table (');
    buffer.write(columns.join(', '));
    buffer.write(') values ');

    for (var i = 0; i < data.length; i++) {
      buffer.write('(');
      final row = data[i];
      for (var j = 0; j < columns.length; j++) {
        buffer.write('?');
        bindings.add(row[columns[j]]);
        if (j < columns.length - 1) buffer.write(', ');
      }
      buffer.write(')');
      if (i < data.length - 1) buffer.write(', ');
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileUpdate({
    required String table,
    required Map<String, Object?> data,
    required List<Map<String, dynamic>> wheres,
    List<Map<String, dynamic>> joins = const [],
    List<Map<String, dynamic>> orders = const [],
    int? limit,
    int? offset,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('update $table set ');
    final entries = data.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      buffer.write('${entries[i].key} = ?');
      bindings.add(entries[i].value);
      if (i < entries.length - 1) buffer.write(', ');
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      for (var i = 0; i < wheres.length; i++) {
        final w = wheres[i];
        if (i > 0) buffer.write(' ${w['boolean']} ');
        if (w['type'] == 'raw') {
          buffer.write('(${w['sql']})');
          bindings.addAll(w['bindings'] as List<Object?>);
        } else {
          final value = w['value'];
          if (value is Expression) {
            buffer.write('${w['column']} ${w['comparator']} ${value.sql}');
          } else {
            buffer.write('${w['column']} ${w['comparator']} ?');
            bindings.add(value);
          }
        }
      }
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileDelete({
    required String table,
    required List<Map<String, dynamic>> wheres,
    List<Map<String, dynamic>> joins = const [],
    List<Map<String, dynamic>> orders = const [],
    int? limit,
    int? offset,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('delete from $table');

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      for (var i = 0; i < wheres.length; i++) {
        final w = wheres[i];
        if (i > 0) buffer.write(' ${w['boolean']} ');
        if (w['type'] == 'raw') {
          buffer.write('(${w['sql']})');
          bindings.addAll(w['bindings'] as List<Object?>);
        } else {
          final value = w['value'];
          if (value is Expression) {
            buffer.write('${w['column']} ${w['comparator']} ${value.sql}');
          } else {
            buffer.write('${w['column']} ${w['comparator']} ?');
            bindings.add(value);
          }
        }
      }
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileInsertGetId({
    required String table,
    required Map<String, Object?> data,
    String idColumn = 'id',
  }) {
    return compileInsert(table: table, data: [data]);
  }

  @override
  CompiledQuery compileIncrement({
    required String table,
    required String column,
    required int amount,
    Map<String, Object?>? extra,
    required List<Map<String, dynamic>> wheres,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('update $table set $column = $column + ?');
    bindings.add(amount);

    if (extra != null && extra.isNotEmpty) {
      for (final entry in extra.entries) {
        buffer.write(', ${entry.key} = ?');
        bindings.add(entry.value);
      }
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      for (var i = 0; i < wheres.length; i++) {
        final w = wheres[i];
        if (i > 0) buffer.write(' ${w['boolean']} ');
        if (w['type'] == 'raw') {
          buffer.write('(${w['sql']})');
          bindings.addAll(w['bindings'] as List<Object?>);
        } else {
          final value = w['value'];
          if (value is Expression) {
            buffer.write('${w['column']} ${w['comparator']} ${value.sql}');
          } else {
            buffer.write('${w['column']} ${w['comparator']} ?');
            bindings.add(value);
          }
        }
      }
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileDecrement({
    required String table,
    required String column,
    required int amount,
    Map<String, Object?>? extra,
    required List<Map<String, dynamic>> wheres,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('update $table set $column = $column - ?');
    bindings.add(amount);

    if (extra != null && extra.isNotEmpty) {
      for (final entry in extra.entries) {
        buffer.write(', ${entry.key} = ?');
        bindings.add(entry.value);
      }
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      for (var i = 0; i < wheres.length; i++) {
        final w = wheres[i];
        if (i > 0) buffer.write(' ${w['boolean']} ');
        if (w['type'] == 'raw') {
          buffer.write('(${w['sql']})');
          bindings.addAll(w['bindings'] as List<Object?>);
        } else {
          final value = w['value'];
          if (value is Expression) {
            buffer.write('${w['column']} ${w['comparator']} ${value.sql}');
          } else {
            buffer.write('${w['column']} ${w['comparator']} ?');
            bindings.add(value);
          }
        }
      }
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileTruncate({required String table}) {
    return CompiledQuery(sql: 'delete from $table', bindings: []);
  }

  @override
  CompiledQuery compileInsertOrIgnore({
    required String table,
    required List<Map<String, Object?>> data,
  }) {
    final compiled = compileInsert(table: table, data: data);
    return CompiledQuery(
      sql: compiled.sql.replaceFirst('insert into', 'insert or ignore into'),
      bindings: compiled.bindings,
    );
  }

  @override
  CompiledQuery compileUpsert({
    required String table,
    required List<Map<String, Object?>> data,
    required List<String> uniqueBy,
    List<String>? update,
  }) {
    final compiled = compileInsert(table: table, data: data);
    final updateCols =
        update ?? data.first.keys.where((k) => !uniqueBy.contains(k)).toList();
    if (updateCols.isEmpty) return compiled;
    final setClauses = updateCols.map((c) => '$c = excluded.$c').join(', ');
    return CompiledQuery(
      sql:
          '${compiled.sql} on conflict(${uniqueBy.join(', ')}) do update set $setClauses',
      bindings: compiled.bindings,
    );
  }
}

/// Mock driver for testing the core package without database dependencies.
class MockDriver implements DatabaseDriver {
  final List<String> executedSql = [];
  final List<List<Object?>> executedParams = [];
  List<Map<String, Object?>> mockResults = [];
  int affectedRows = 0;

  @override
  SqlGrammar get grammar => MockGrammar();

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    executedSql.add(sql);
    executedParams.add(params);
    return mockResults.map((r) => LaconicResult.fromMap(r)).toList();
  }

  @override
  Stream<LaconicResult> selectStream(
    String sql, [
    List<Object?> params = const [],
  ]) async* {
    yield* Stream.fromIterable(await select(sql, params));
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    executedSql.add(sql);
    executedParams.add(params);
  }

  @override
  Future<int> affectingStatement(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    executedSql.add(sql);
    executedParams.add(params);
    return affectedRows;
  }

  @override
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    executedSql.add(sql);
    executedParams.add(params);
    return 1;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    return await action();
  }

  @override
  Future<void> close() async {}
}
