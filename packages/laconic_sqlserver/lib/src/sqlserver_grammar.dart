import 'dart:convert';

import 'package:laconic/laconic.dart';

part 'sqlserver_schema.dart';

/// SQL Server 2022+ SQL grammar.
///
/// Handles SQL Server SQL syntax with `?` placeholders for parameter binding.
class SqlserverGrammar extends SqlGrammar with _SqlserverSchema {
  @override
  String get randomOrderExpression => 'newid()';

  @override
  CompiledQuery compileSelect({
    required String table,
    required List<String> columns,
    required List<Map<String, dynamic>> wheres,
    required List<Map<String, dynamic>> joins,
    required List<Map<String, dynamic>> orders,
    required List<String> groups,
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
    if (distinct) {
      buffer.write('distinct ');
    }
    if (limit != null && (offset == null || limit == 0)) {
      buffer.write('top ($limit) ');
    }
    buffer.write(_compileColumns(columns));
    bindings.addAll(selectBindings);
    if (fromSubquery != null) {
      if (fromAlias != null) {
        buffer.write(' from (${fromSubquery.sql}) as $fromAlias');
      } else {
        buffer.write(' from ${fromSubquery.sql}');
      }
      bindings.addAll(fromSubquery.bindings);
    } else {
      buffer.write(' from $table');
    }

    if (indexHints.isNotEmpty) {
      throw LaconicException('SQL Server does not support MySQL index hints');
    }
    if (locks.isNotEmpty) {
      if (fromSubquery != null) {
        throw LaconicException('SQL Server lock hints require a base table');
      }
      final hints = <String>[];
      for (final lock in locks) {
        switch (lock['type']) {
          case 'for_update':
            hints.addAll(['updlock', 'rowlock']);
          case 'for_share':
            hints.addAll(['holdlock', 'rowlock']);
          case 'raw':
            hints.add(lock['value'] as String);
        }
      }
      buffer.write(' with (${hints.toSet().join(', ')})');
    }

    if (joins.isNotEmpty) {
      buffer.write(_compileJoins(joins, bindings));
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(wheres, bindings));
    }

    if (groups.isNotEmpty) {
      buffer.write(_compileGroups(groups));
      bindings.addAll(groupBindings);
    }

    if (havings.isNotEmpty) {
      buffer.write(' having ');
      buffer.write(_compileHavings(havings, bindings));
    }

    if (orders.isNotEmpty) {
      buffer.write(_compileOrders(orders, bindings));
    }

    if (limit != 0 && offset != null) {
      if (orders.isEmpty) {
        buffer.write(distinct ? ' order by 1' : ' order by (select 0)');
      }
      buffer.write(' offset ? rows');
      bindings.add(offset);
      if (limit != null) {
        buffer.write(' fetch next ? rows only');
        bindings.add(limit);
      }
    } else if (limit == null && orders.isNotEmpty) {
      // SQL Server requires TOP or OFFSET for ORDER BY inside a derived table.
      buffer.write(' offset 0 rows');
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
        final value = row[columns[j]];
        buffer.write(value is Expression ? value.sql : '?');
        if (value is! Expression) {
          bindings.add(value);
        }
        if (j < columns.length - 1) {
          buffer.write(', ');
        }
      }
      buffer.write(')');
      if (i < data.length - 1) {
        buffer.write(', ');
      }
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileUpdate({
    required String table,
    required Map<String, Object?> data,
    required List<Map<String, dynamic>> wheres,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('update $table set ');

    final entries = data.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final value = entries[i].value;
      buffer.write(
        '${entries[i].key} = ${value is Expression ? value.sql : '?'}',
      );
      if (value is! Expression) {
        bindings.add(value);
      }
      if (i < entries.length - 1) {
        buffer.write(', ');
      }
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(wheres, bindings));
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileDelete({
    required String table,
    required List<Map<String, dynamic>> wheres,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('delete from $table');

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(wheres, bindings));
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileInsertGetId({
    required String table,
    required Map<String, Object?> data,
    String idColumn = 'id',
  }) {
    final compiled = compileInsert(table: table, data: [data]);
    final columns = data.keys.join(', ');
    final prefix = 'insert into $table ($columns)';
    return CompiledQuery(
      sql:
          '$prefix output inserted.$idColumn${compiled.sql.substring(prefix.length)}',
      bindings: compiled.bindings,
    );
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
        final value = entry.value;
        buffer.write(
          ', ${entry.key} = ${value is Expression ? value.sql : '?'}',
        );
        if (value is! Expression) {
          bindings.add(value);
        }
      }
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(wheres, bindings));
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
        final value = entry.value;
        buffer.write(
          ', ${entry.key} = ${value is Expression ? value.sql : '?'}',
        );
        if (value is! Expression) {
          bindings.add(value);
        }
      }
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(wheres, bindings));
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileTruncate({required String table}) {
    return CompiledQuery(sql: 'truncate table $table', bindings: []);
  }

  @override
  CompiledQuery compileInsertOrIgnore({
    required String table,
    required List<Map<String, Object?>> data,
  }) {
    throw LaconicException(
      'SQL Server does not support insertOrIgnore; use upsert with explicit uniqueBy',
    );
  }

  @override
  String compileInsertOrIgnoreUsing({
    required String table,
    required List<String> columns,
    required String sql,
  }) {
    throw LaconicException('SQL Server does not support insertOrIgnoreUsing');
  }

  @override
  CompiledQuery compileUpsert({
    required String table,
    required List<Map<String, Object?>> data,
    required List<String> uniqueBy,
    List<String>? update,
  }) {
    if (uniqueBy.isEmpty) {
      throw LaconicException('SQL Server upsert requires uniqueBy');
    }
    final columns = data.first.keys.toList();
    if (uniqueBy.any((column) => !columns.contains(column))) {
      throw LaconicException(
        'SQL Server upsert keys must be included in the data',
      );
    }
    final updates =
        update ?? columns.where((c) => !uniqueBy.contains(c)).toList();
    if (updates.any((column) => !columns.contains(column))) {
      throw LaconicException(
        'SQL Server upsert update columns must be included in the data',
      );
    }
    final bindings = <Object?>[];
    final rows = data
        .map((row) {
          final values = columns.map((column) {
            final value = row[column];
            if (value is Expression) return value.sql;
            bindings.add(value);
            return '?';
          });
          return '(${values.join(', ')})';
        })
        .join(', ');
    final on = uniqueBy
        .map((c) => 'laconic_target.$c = laconic_source.$c')
        .join(' and ');
    final sql = StringBuffer(
      'merge into $table with (holdlock) as laconic_target '
      'using (values $rows) as laconic_source (${columns.join(', ')}) on $on',
    );
    if (updates.isNotEmpty) {
      sql.write(' when matched then update set ');
      sql.write(updates.map((c) => '$c = laconic_source.$c').join(', '));
    }
    sql.write(
      ' when not matched then insert (${columns.join(', ')}) values '
      '(${columns.map((c) => 'laconic_source.$c').join(', ')});',
    );
    return CompiledQuery(sql: sql.toString(), bindings: bindings);
  }

  @override
  String compileAggregateExpression(
    String function,
    String column, {
    bool distinct = false,
  }) {
    final argument =
        function.toUpperCase() == 'AVG' ? 'cast($column as float)' : column;
    return '$function(${distinct ? 'DISTINCT ' : ''}$argument)';
  }

  /// Compiles column names for SELECT clause.
  String _compileColumns(List<String> columns) {
    if (columns.isEmpty || (columns.length == 1 && columns[0] == '*')) {
      return '*';
    }
    return columns
        .map((column) => column == '1' ? '1 as laconic_exists' : column)
        .join(', ');
  }

  /// Compiles JOIN clauses.
  String _compileJoins(
    List<Map<String, dynamic>> joins,
    List<Object?> bindings,
  ) {
    final buffer = StringBuffer();

    for (final join in joins) {
      final type = join['type'] as String? ?? 'inner';
      final table = join['table'] as String;
      final conditions = join['conditions'] as List<Map<String, dynamic>>;
      final tableBindings = join['tableBindings'] as List<Object?>?;
      if (tableBindings != null) {
        bindings.addAll(tableBindings);
      }

      if (type == 'lateral') {
        final joinType = join['joinType'] as String? ?? 'inner';
        if (joinType != 'inner' && joinType != 'left') {
          throw LaconicException(
            'SQL Server APPLY supports only inner and left lateral joins',
          );
        }
        buffer.write(' ${joinType == 'left' ? 'outer' : 'cross'} apply $table');
        continue;
      }

      switch (type) {
        case 'left':
          buffer.write(' left join $table');
        case 'right':
          buffer.write(' right join $table');
        case 'cross':
          buffer.write(' cross join $table');
        case 'straight':
          throw LaconicException('SQL Server does not support STRAIGHT_JOIN');
        case 'inner':
        default:
          buffer.write(' join $table');
      }

      if (conditions.isNotEmpty) {
        buffer.write(' on ');
        buffer.write(_compileJoinConditions(conditions, bindings));
      }
    }

    return buffer.toString();
  }

  /// Compiles JOIN conditions.
  String _compileJoinConditions(
    List<Map<String, dynamic>> conditions,
    List<Object?> bindings,
  ) {
    final parts = <String>[];

    for (var i = 0; i < conditions.length; i++) {
      final condition = conditions[i];
      final boolean = i == 0 ? '' : ' ${condition['boolean']} ';
      final type =
          condition['type'] ??
          'on'; // Default to 'on' for backward compatibility

      if (type == 'on') {
        // ON clause: column = column
        parts.add(
          '$boolean${condition['left']} ${condition['comparator']} ${condition['right']}',
        );
      } else if (type == 'where') {
        // WHERE clause within JOIN
        final value = condition['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${condition['column']} ${condition['comparator']} ${value.sql}',
          );
        } else {
          parts.add(
            '$boolean${condition['column']} ${condition['comparator']} ?',
          );
          bindings.add(value);
        }
      } else if (type == 'column') {
        // WHERE column1 = column2
        parts.add(
          '$boolean${condition['first']} ${condition['comparator']} ${condition['second']}',
        );
      } else if (type == 'null') {
        // WHERE column IS NULL or WHERE column IS NOT NULL
        final column = condition['column'];
        final not = condition['not'] as bool;
        final nullKeyword = not ? 'is not null' : 'is null';
        parts.add('$boolean$column $nullKeyword');
      } else if (type == 'in') {
        // WHERE column IN (?, ?, ?) or WHERE column NOT IN (?, ?, ?)
        final column = condition['column'];
        final values = condition['values'] as List<Object?>;
        final not = condition['not'] as bool;
        final inKeyword = not ? 'not in' : 'in';

        if (values.isEmpty) {
          // Handle empty IN clause - always false for IN, always true for NOT IN
          parts.add('$boolean${not ? '1 = 1' : '1 = 0'}');
        } else {
          final placeholders = List.filled(values.length, '?').join(', ');
          parts.add('$boolean$column $inKeyword ($placeholders)');
          bindings.addAll(values);
        }
      } else if (type == 'between') {
        // WHERE column BETWEEN ? AND ? or WHERE column NOT BETWEEN ? AND ?
        final column = condition['column'];
        final values = condition['values'] as List<Object?>;
        final not = condition['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add('$boolean$column $betweenKeyword ? and ?');
        bindings.addAll(values);
      } else if (type == 'betweenColumns') {
        // WHERE column BETWEEN column1 AND column2
        final column = condition['column'];
        final betweenColumns = condition['betweenColumns'] as List<String>;
        final not = condition['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add(
          '$boolean$column $betweenKeyword ${betweenColumns[0]} and ${betweenColumns[1]}',
        );
      } else if (type == 'raw') {
        parts.add('$boolean(${condition['sql']})');
        bindings.addAll(condition['bindings'] as List<Object?>);
      } else if (type == 'exists') {
        final not = condition['not'] as bool;
        final keyword = not ? 'not exists' : 'exists';
        parts.add('$boolean$keyword (${condition['sql']})');
        bindings.addAll(condition['bindings'] as List<Object?>);
      } else if (type == 'nested') {
        final nested = _compileJoinConditions(
          condition['conditions'] as List<Map<String, dynamic>>,
          bindings,
        );
        parts.add('$boolean($nested)');
      }
    }

    return parts.join('');
  }

  /// Compiles WHERE clauses.
  String _compileWheres(
    List<Map<String, dynamic>> wheres,
    List<Object?> bindings,
  ) {
    final parts = <String>[];

    for (var i = 0; i < wheres.length; i++) {
      final where = wheres[i];
      final boolean = i == 0 ? '' : ' ${where['boolean']} ';
      final type = where['type'];

      if (type == 'basic') {
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${where['column']} ${where['comparator']} ${value.sql}',
          );
        } else {
          parts.add('$boolean${where['column']} ${where['comparator']} ?');
          bindings.add(value);
        }
      } else if (type == 'like') {
        final not = where['not'] as bool;
        final keyword = not ? 'not like' : 'like';
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            '${boolean}lower(${where['column']}) $keyword lower(${value.sql})',
          );
        } else {
          parts.add('${boolean}lower(${where['column']}) $keyword lower(?)');
          bindings.add(value);
        }
      } else if (type == 'subquery') {
        parts.add(
          '$boolean${where['column']} ${where['comparator']} (${where['sql']})',
        );
        bindings.addAll(where['bindings'] as List<Object?>);
      } else if (type == 'binary') {
        throw LaconicException('SQL Server does not support whereBinary');
      } else if (type == 'jsonContains' || type == 'jsonOverlaps') {
        parts.add('$boolean${_compileJsonMembership(where, bindings)}');
      } else if (type == 'jsonContainsKey') {
        final not = where['not'] as bool;
        parts.add(
          '${boolean}coalesce(json_path_exists(cast(${where['column']} as nvarchar(max)), ?), 0) = ${not ? 0 : 1}',
        );
        bindings.add(where['path']);
      } else if (type == 'jsonLength') {
        final path = where['path'] as String?;
        final column = "cast(${where['column']} as nvarchar(max))";
        final source = path == null ? column : 'json_query($column, ?)';
        if (path != null) bindings.add(path);
        parts.add(
          '$boolean(select case when isjson(laconic_document.document) = 1 '
          'then (select count(*) from openjson(laconic_document.document)) end '
          'from (select $source as document) as laconic_document) ${where['comparator']} ?',
        );
        bindings.add(where['value']);
      } else if (type == 'fullText') {
        final columns = (where['columns'] as List<String>).join(', ');
        final options = where['options'] as Map<String, dynamic>;
        if (options.keys.any((key) => key != 'mode') ||
            ![null, 'natural language', 'boolean'].contains(options['mode'])) {
          throw LaconicException(
            'SQL Server full text supports only natural language or boolean mode',
          );
        }
        final function = options['mode'] == 'boolean' ? 'contains' : 'freetext';
        final value = where['value'];
        parts.add(
          '$boolean$function(($columns), ${value is Expression ? value.sql : '?'})',
        );
        if (value is! Expression) bindings.add(value);
      } else if (type == 'column') {
        // WHERE column1 = column2
        parts.add(
          '$boolean${where['first']} ${where['comparator']} ${where['second']}',
        );
      } else if (type == 'in') {
        // WHERE column IN (?, ?, ?) or WHERE column NOT IN (?, ?, ?)
        final column = where['column'];
        final values = where['values'] as List<Object?>;
        final not = where['not'] as bool;
        final inKeyword = not ? 'not in' : 'in';

        if (values.isEmpty) {
          // Handle empty IN clause - always false for IN, always true for NOT IN
          parts.add('$boolean${not ? '1 = 1' : '1 = 0'}');
        } else {
          final placeholders = List.filled(values.length, '?').join(', ');
          parts.add('$boolean$column $inKeyword ($placeholders)');
          bindings.addAll(values);
        }
      } else if (type == 'inSubquery') {
        final not = where['not'] as bool;
        parts.add(
          '$boolean${where['column']} ${not ? 'not in' : 'in'} (${where['sql']})',
        );
        bindings.addAll(where['bindings'] as List<Object?>);
      } else if (type == 'null') {
        // WHERE column IS NULL or WHERE column IS NOT NULL
        final column = where['column'];
        final not = where['not'] as bool;
        final nullKeyword = not ? 'is not null' : 'is null';
        parts.add('$boolean$column $nullKeyword');
      } else if (type == 'between') {
        // WHERE column BETWEEN ? AND ? or WHERE column NOT BETWEEN ? AND ?
        final column = where['column'];
        final values = where['values'] as List<Object?>;
        final not = where['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add('$boolean$column $betweenKeyword ? and ?');
        bindings.addAll(values);
      } else if (type == 'betweenColumns') {
        // WHERE column BETWEEN column1 AND column2
        final column = where['column'];
        final betweenColumns = where['betweenColumns'] as List<String>;
        final not = where['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add(
          '$boolean$column $betweenKeyword ${betweenColumns[0]} and ${betweenColumns[1]}',
        );
      } else if (type == 'integerInRaw') {
        final column = where['column'];
        final values = where['values'] as List<int>;
        final not = where['not'] as bool;
        if (values.isEmpty) {
          parts.add('$boolean${not ? '1 = 1' : '1 = 0'}');
        } else {
          parts.add(
            '$boolean$column ${not ? 'not in' : 'in'} (${values.join(', ')})',
          );
        }
      } else if (type == 'rowValues') {
        parts.add('$boolean${_compileRowValues(where, bindings)}');
      } else if (type == 'valueBetween') {
        final columns = where['columns'] as List<String>;
        final not = where['not'] as bool;
        final keyword = not ? 'not between' : 'between';
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${value.sql} $keyword ${columns[0]} and ${columns[1]}',
          );
        } else {
          parts.add('$boolean? $keyword ${columns[0]} and ${columns[1]}');
          bindings.add(value);
        }
      } else if (type == 'nullSafeEquals') {
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${where['column']} is not distinct from ${value.sql}',
          );
        } else {
          parts.add('$boolean${where['column']} is not distinct from ?');
          bindings.add(value);
        }
      } else if (type == 'all') {
        // WHERE (col1 = ? AND col2 = ? AND col3 = ?)
        final columns = where['columns'] as List<String>;
        final comparator = where['comparator'];
        final value = where['value'];
        final conditions = columns
            .map((col) => '$col $comparator ?')
            .join(' and ');
        parts.add('$boolean($conditions)');
        for (var j = 0; j < columns.length; j++) {
          bindings.add(value);
        }
      } else if (type == 'any') {
        // WHERE (col1 = ? OR col2 = ? OR col3 = ?)
        final columns = where['columns'] as List<String>;
        final comparator = where['comparator'];
        final value = where['value'];
        final conditions = columns
            .map((col) => '$col $comparator ?')
            .join(' or ');
        parts.add('$boolean($conditions)');
        for (var j = 0; j < columns.length; j++) {
          bindings.add(value);
        }
      } else if (type == 'none') {
        // WHERE NOT (col1 = ? OR col2 = ? OR col3 = ?)
        final columns = where['columns'] as List<String>;
        final comparator = where['comparator'];
        final value = where['value'];
        final conditions = columns
            .map((col) => '$col $comparator ?')
            .join(' or ');
        parts.add('${boolean}not ($conditions)');
        for (var j = 0; j < columns.length; j++) {
          bindings.add(value);
        }
      } else if (type == 'nested') {
        final nested = _compileWheres(where['conditions'], bindings);
        final not = where['not'] as bool? ?? false;
        parts.add('$boolean${not ? 'not ' : ''}($nested)');
      } else if (type == 'raw') {
        parts.add('$boolean(${where['sql']})');
        bindings.addAll(where['bindings'] as List<Object?>);
      } else if (type == 'exists') {
        final not = where['not'] as bool;
        final keyword = not ? 'not exists' : 'exists';
        parts.add('$boolean$keyword (${where['sql']})');
        bindings.addAll(where['bindings'] as List<Object?>);
      } else if (type == 'date') {
        final expr = _dateExpression(
          where['dateType'] as String,
          where['column'] as String,
        );
        parts.add('$boolean$expr ${where['comparator'] ?? '='} ?');
        bindings.add(where['value']);
      }
    }

    return parts.join('');
  }

  String _compileRowValues(Map<String, dynamic> where, List<Object?> bindings) {
    final columns = where['columns'] as List<String>;
    final values = where['values'] as List<Object?>;
    final operator = where['operator'] as String;
    String comparison(int i, String op) {
      final value = values[i];
      if (value is Expression) return '${columns[i]} $op ${value.sql}';
      bindings.add(value);
      return '${columns[i]} $op ?';
    }

    if (operator == '=' || operator == '!=' || operator == '<>') {
      final equalities = [
        for (var i = 0; i < columns.length; i++) comparison(i, '='),
      ];
      return '${operator == '=' ? '' : 'not '}(${equalities.join(' and ')})';
    }
    if (!['<', '<=', '>', '>='].contains(operator)) {
      throw LaconicException(
        'SQL Server does not support row comparison $operator',
      );
    }
    final alternatives = <String>[];
    for (var i = 0; i < columns.length; i++) {
      final conditions = [for (var j = 0; j < i; j++) comparison(j, '=')];
      conditions.add(
        comparison(i, i == columns.length - 1 ? operator : operator[0]),
      );
      alternatives.add('(${conditions.join(' and ')})');
    }
    return '(${alternatives.join(' or ')})';
  }

  String _compileJsonMembership(
    Map<String, dynamic> where,
    List<Object?> bindings,
  ) {
    final value = where['value'];
    final values = value is List ? value : [value];
    if (values.any((v) => v is Map || v is List || v is Expression)) {
      throw LaconicException(
        'SQL Server JSON membership supports scalars and flat scalar arrays',
      );
    }
    final overlaps = where['type'] == 'jsonOverlaps';
    final not = where['not'] as bool;
    final path = where['path'] as String?;
    final column = "cast(${where['column']} as nvarchar(max))";
    // JSON_QUERY selects an array path; OPENJSON preserves scalar JSON types.
    final source = path == null ? column : 'json_query($column, ?)';
    final checks = <String>[];
    for (final candidate in values) {
      if (path != null) bindings.add(path);
      bindings.add(jsonEncode([candidate]));
      checks.add(
        'exists (select 1 from (select $source as document) as laconic_document '
        'cross apply openjson(laconic_document.document) as laconic_json '
        'cross join openjson(?) as laconic_candidate '
        'where isjson(laconic_document.document, ARRAY) = 1 and '
        'laconic_json.type = laconic_candidate.type and '
        '(laconic_json.value collate Latin1_General_100_BIN2 = '
        'laconic_candidate.value collate Latin1_General_100_BIN2 '
        'and (laconic_json.type <> 1 or datalength(laconic_json.value) = '
        'datalength(laconic_candidate.value)) '
        'or (laconic_json.type = 2 and try_convert(float, laconic_json.value) = '
        'try_convert(float, laconic_candidate.value) and '
        'try_convert(decimal(38, 18), laconic_json.value) = '
        'try_convert(decimal(38, 18), laconic_candidate.value)) '
        'or (laconic_json.type = 0 and laconic_candidate.type = 0)))',
      );
    }
    final String predicate;
    if (checks.isEmpty) {
      if (!overlaps && path != null) bindings.add(path);
      predicate = overlaps ? '1 = 0' : 'isjson($source, ARRAY) = 1';
    } else {
      predicate = checks.join(overlaps ? ' or ' : ' and ');
    }
    return '${not ? 'not ' : ''}($predicate)';
  }

  /// Returns a complete SQL expression for a date-part extraction.
  /// The returned string already includes the column reference.
  String _dateExpression(String dateType, String column) {
    switch (dateType) {
      case 'date':
        return 'cast($column as date)';
      case 'time':
        return 'cast($column as time)';
      case 'day':
        return 'day($column)';
      case 'month':
        return 'month($column)';
      case 'year':
        return 'year($column)';
      default:
        return '$dateType($column)';
    }
  }

  /// Compiles ORDER BY clauses.
  String _compileOrders(
    List<Map<String, dynamic>> orders,
    List<Object?> bindings,
  ) {
    final buffer = StringBuffer();
    buffer.write(' order by ');

    for (var i = 0; i < orders.length; i++) {
      final order = orders[i];
      if (order['type'] == 'raw') {
        buffer.write(order['sql']);
        bindings.addAll(order['bindings'] as List<Object?>);
      } else {
        buffer.write('${order['column']} ${order['direction']}');
      }
      if (i < orders.length - 1) {
        buffer.write(', ');
      }
    }

    return buffer.toString();
  }

  /// Compiles GROUP BY clauses.
  String _compileGroups(List<String> groups) {
    return ' group by ${groups.join(', ')}';
  }

  /// Compiles HAVING clauses.
  String _compileHavings(
    List<Map<String, dynamic>> havings,
    List<Object?> bindings,
  ) {
    final parts = <String>[];

    for (var i = 0; i < havings.length; i++) {
      final having = havings[i];
      final boolean = i == 0 ? '' : ' ${having['boolean']} ';

      if (having['type'] == 'raw') {
        parts.add('$boolean(${having['sql']})');
        bindings.addAll(having['bindings'] as List<Object?>);
      } else if (having['type'] == 'nested') {
        final nested = _compileHavings(having['conditions'], bindings);
        parts.add('$boolean($nested)');
      } else if (having['type'] == 'null') {
        final not = having['not'] as bool;
        parts.add(
          '$boolean${having['column']} ${not ? 'is not null' : 'is null'}',
        );
      } else if (having['type'] == 'between') {
        final not = having['not'] as bool;
        parts.add(
          '$boolean${having['column']} ${not ? 'not between' : 'between'} ? and ?',
        );
        bindings.addAll(having['values'] as List<Object?>);
      } else {
        final value = having['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${having['column']} ${having['comparator']} ${value.sql}',
          );
        } else {
          parts.add('$boolean${having['column']} ${having['comparator']} ?');
          bindings.add(value);
        }
      }
    }

    return parts.join('');
  }
}
