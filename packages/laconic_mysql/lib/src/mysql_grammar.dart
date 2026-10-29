import 'dart:convert';

import 'package:laconic/laconic.dart';

part 'mysql_schema.dart';

/// MySQL-specific SQL grammar.
///
/// Handles MySQL SQL syntax with `?` placeholders for parameter binding.
class MysqlGrammar extends SqlGrammar with _MysqlSchema {
  @override
  String compileJsonSelector(String column, String path) =>
      'json_unquote(json_extract(${wrap(column)}, ${compileSchemaLiteral(jsonPath(path))}))';

  @override
  String compileBasicPredicate(
    String column,
    String comparator,
    Object? value,
    List<Object?> bindings,
  ) {
    if (column.contains('->') && value is bool) {
      final selector = splitJsonSelector(column);
      return "json_extract(${wrap(selector.column)}, ${compileSchemaLiteral(jsonPath(selector.path))}) $comparator json_extract(${parameter(jsonEncode(value), bindings)}, '\$')";
    }
    return super.compileBasicPredicate(column, comparator, value, bindings);
  }

  @override
  String compileNullPredicate(String column, bool not) {
    if (!column.contains('->')) return super.compileNullPredicate(column, not);
    final selector = splitJsonSelector(column);
    final extract =
        'json_extract(${wrap(selector.column)}, ${compileSchemaLiteral(jsonPath(selector.path))})';
    return not
        ? "($extract is not null and json_type($extract) <> 'NULL')"
        : "($extract is null or json_type($extract) = 'NULL')";
  }

  @override
  String compileJsonUpdate(
    String source,
    String path,
    Object? value,
    List<Object?> bindings,
  ) {
    final sqlValue =
        value is Map || value is List || value is bool
            ? "json_extract(${parameter(jsonEncode(value), bindings)}, '\$')"
            : parameter(value, bindings);
    return 'json_set($source, ${compileSchemaLiteral(jsonPath(path))}, $sqlValue)';
  }

  @override
  String wrapAssignmentColumn(String column) => wrap(column);

  @override
  String get randomOrderExpression => 'rand()';

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
    if (distinct) {
      buffer.write('distinct ');
    }
    buffer.write(_compileColumns(columns));
    bindings.addAll(selectBindings);
    if (fromSubquery != null) {
      if (fromAlias != null) {
        buffer.write(
          ' from (${fromSubquery.sql}) as ${quoteSchemaIdentifier(fromAlias)}',
        );
      } else {
        buffer.write(' from ${fromSubquery.sql}');
      }
      bindings.addAll(fromSubquery.bindings);
    } else {
      buffer.write(' from ${wrapTable(table)}');
    }

    if (fromSubquery == null) {
      for (final hint in indexHints) {
        final keyword = switch (hint['type']) {
          'use' => 'use',
          'force' => 'force',
          _ => 'ignore',
        };
        buffer.write(
          ' $keyword index (${hint['index']!.split(', ').map(wrap).join(', ')})',
        );
      }
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

    if (limit != null) {
      buffer.write(' limit ?');
      bindings.add(limit);
    } else if (offset != null) {
      buffer.write(' limit 18446744073709551615');
    }

    if (offset != null) {
      buffer.write(' offset ?');
      bindings.add(offset);
    }

    for (final lock in locks) {
      if (lock['type'] == 'for_update') {
        buffer.write(' for update');
      } else if (lock['type'] == 'for_share') {
        buffer.write(' lock in share mode');
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

    buffer.write('insert into ${wrapTable(table)} (');
    buffer.write(columns.map(wrap).join(', '));
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
    List<Map<String, dynamic>> joins = const [],
    List<Map<String, dynamic>> orders = const [],
    int? limit,
    int? offset,
  }) {
    final bindings = <Object?>[];
    if ((offset != null && offset != 0) ||
        (joins.isNotEmpty && (orders.isNotEmpty || limit != null))) {
      throw LaconicException(
        'MySQL/MariaDB writes do not support OFFSET or ORDER BY/LIMIT with JOIN',
      );
    }
    final joinSql = _compileJoins(joins, bindings);
    final assignments = compileAssignments(data, bindings);
    final sql = StringBuffer(
      'update ${wrapTable(table)}$joinSql set $assignments',
    );
    if (wheres.isNotEmpty) {
      sql.write(' where ${_compileWheres(wheres, bindings)}');
    }
    if (orders.isNotEmpty) sql.write(_compileOrders(orders, bindings));
    if (limit != null) sql.write(' limit ${parameter(limit, bindings)}');
    return CompiledQuery(sql: sql.toString(), bindings: bindings);
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
    final bindings = <Object?>[];
    if ((offset != null && offset != 0) ||
        (joins.isNotEmpty && (orders.isNotEmpty || limit != null))) {
      throw LaconicException(
        'MySQL/MariaDB writes do not support OFFSET or ORDER BY/LIMIT with JOIN',
      );
    }
    final sql = StringBuffer(
      joins.isEmpty
          ? 'delete from ${wrapTable(table)}'
          : 'delete ${tableReference(table)} from ${wrapTable(table)}',
    );
    sql.write(_compileJoins(joins, bindings));
    if (wheres.isNotEmpty) {
      sql.write(' where ${_compileWheres(wheres, bindings)}');
    }
    if (orders.isNotEmpty) sql.write(_compileOrders(orders, bindings));
    if (limit != null) sql.write(' limit ${parameter(limit, bindings)}');
    return CompiledQuery(sql: sql.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileInsertGetId({
    required String table,
    required Map<String, Object?> data,
    String idColumn = 'id',
  }) {
    // For MySQL, insertGetId is identical to insert
    // MySQL uses lastInsertId to get the inserted ID
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

    buffer.write(
      'update ${wrapTable(table)} set ${wrap(column)} = ${wrap(column)} + ?',
    );
    bindings.add(amount);

    if (extra != null && extra.isNotEmpty) {
      for (final entry in extra.entries) {
        final value = entry.value;
        buffer.write(
          ', ${wrap(entry.key)} = ${value is Expression ? value.sql : '?'}',
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

    buffer.write(
      'update ${wrapTable(table)} set ${wrap(column)} = ${wrap(column)} - ?',
    );
    bindings.add(amount);

    if (extra != null && extra.isNotEmpty) {
      for (final entry in extra.entries) {
        final value = entry.value;
        buffer.write(
          ', ${wrap(entry.key)} = ${value is Expression ? value.sql : '?'}',
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
    return CompiledQuery(
      sql: 'truncate table ${wrapTable(table)}',
      bindings: [],
    );
  }

  @override
  CompiledQuery compileInsertOrIgnore({
    required String table,
    required List<Map<String, Object?>> data,
  }) {
    final compiled = compileInsert(table: table, data: data);
    return CompiledQuery(
      sql: compiled.sql.replaceFirst('insert into', 'insert ignore into'),
      bindings: compiled.bindings,
    );
  }

  @override
  String compileInsertOrIgnoreUsing({
    required String table,
    required List<String> columns,
    required String sql,
  }) {
    return 'insert ignore into ${wrapTable(table)} (${columns.map(wrap).join(', ')}) $sql';
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
    if (updateCols.isEmpty) {
      return compiled;
    }
    final setClauses = updateCols
        .map((c) => '${wrap(c)} = values(${wrap(c)})')
        .join(', ');
    return CompiledQuery(
      sql: '${compiled.sql} on duplicate key update $setClauses',
      bindings: compiled.bindings,
    );
  }

  /// Compiles column names for SELECT clause.
  String _compileColumns(List<Object> columns) {
    if (columns.isEmpty || (columns.length == 1 && columns[0] == '*')) {
      return '*';
    }
    return columns.map(wrap).join(', ');
  }

  /// Compiles JOIN clauses.
  String _compileJoins(
    List<Map<String, dynamic>> joins,
    List<Object?> bindings,
  ) {
    final buffer = StringBuffer();

    for (final join in joins) {
      final type = join['type'] as String? ?? 'inner';
      final table =
          join['tableBindings'] == null
              ? wrapTable(join['table'] as String)
              : join['table'] as String;
      final conditions = join['conditions'] as List<Map<String, dynamic>>;
      final tableBindings = join['tableBindings'] as List<Object?>?;
      if (tableBindings != null) {
        bindings.addAll(tableBindings);
      }

      if (type == 'lateral') {
        final joinType = join['joinType'] as String? ?? 'inner';
        buffer.write(' $joinType join lateral $table on true');
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
          buffer.write(' straight_join $table');
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
          '$boolean${wrap(condition['left'] as String)} ${condition['comparator']} ${wrap(condition['right'] as String)}',
        );
      } else if (type == 'where') {
        parts.add(
          '$boolean${compileBasicPredicate(condition['column'] as String, condition['comparator'] as String, condition['value'], bindings)}',
        );
      } else if (type == 'column') {
        // WHERE column1 = column2
        parts.add(
          '$boolean${wrap(condition['first'] as String)} ${condition['comparator']} ${wrap(condition['second'] as String)}',
        );
      } else if (type == 'null') {
        parts.add(
          '$boolean${compileNullPredicate(condition['column'] as String, condition['not'] as bool)}',
        );
      } else if (type == 'in') {
        // WHERE column IN (?, ?, ?) or WHERE column NOT IN (?, ?, ?)
        final column = wrap(condition['column'] as String);
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
        final column = wrap(condition['column'] as String);
        final values = condition['values'] as List<Object?>;
        final not = condition['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add('$boolean$column $betweenKeyword ? and ?');
        bindings.addAll(values);
      } else if (type == 'betweenColumns') {
        // WHERE column BETWEEN column1 AND column2
        final column = wrap(condition['column'] as String);
        final betweenColumns =
            (condition['betweenColumns'] as List<String>).map(wrap).toList();
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
        parts.add(
          '$boolean${compileBasicPredicate(where['column'] as String, where['comparator'] as String, where['value'], bindings)}',
        );
      } else if (type == 'like') {
        final not = where['not'] as bool;
        final keyword = not ? 'not like' : 'like';
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            '${boolean}lower(${wrap(where['column'] as String)}) $keyword lower(${value.sql})',
          );
        } else {
          parts.add(
            '${boolean}lower(${wrap(where['column'] as String)}) $keyword lower(?)',
          );
          bindings.add(value);
        }
      } else if (type == 'subquery') {
        parts.add(
          '$boolean${wrap(where['column'] as String)} ${where['comparator']} (${where['sql']})',
        );
        bindings.addAll(where['bindings'] as List<Object?>);
      } else if (type == 'binary') {
        final not = where['not'] as bool;
        final operator = not ? '!= binary' : '= binary';
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${wrap(where['column'] as String)} $operator ${value.sql}',
          );
        } else {
          parts.add('$boolean${wrap(where['column'] as String)} $operator ?');
          bindings.add(value);
        }
      } else if (type == 'jsonContains') {
        final not = where['not'] as bool;
        final value = where['value'];
        final path = where['path'] as String?;
        if (value is Expression) {
          if (path == null) {
            parts.add(
              '$boolean${not ? 'not ' : ''}'
              'json_contains(${wrap(where['column'] as String)}, ${value.sql})',
            );
          } else {
            parts.add(
              '$boolean${not ? 'not ' : ''}'
              'json_contains(${wrap(where['column'] as String)}, ${value.sql}, ?)',
            );
            bindings.add(path);
          }
        } else {
          if (path == null) {
            parts.add(
              '$boolean${not ? 'not ' : ''}'
              'json_contains(${wrap(where['column'] as String)}, ?)',
            );
            bindings.add(jsonEncode(value));
          } else {
            parts.add(
              '$boolean${not ? 'not ' : ''}'
              'json_contains(${wrap(where['column'] as String)}, ?, ?)',
            );
            bindings.add(jsonEncode(value));
            bindings.add(path);
          }
        }
      } else if (type == 'jsonContainsKey') {
        final not = where['not'] as bool;
        parts.add(
          '$boolean${not ? 'not ' : ''}'
          "ifnull(json_contains_path(${wrap(where['column'] as String)}, 'one', ?), 0)",
        );
        bindings.add(where['path']);
      } else if (type == 'jsonLength') {
        final path = where['path'] as String?;
        final comparator = where['comparator'];
        if (path != null) {
          parts.add(
            '${boolean}json_length(${wrap(where['column'] as String)}, ?) $comparator ?',
          );
          bindings.add(path);
        } else {
          parts.add(
            '${boolean}json_length(${wrap(where['column'] as String)}) $comparator ?',
          );
        }
        bindings.add(where['value']);
      } else if (type == 'jsonOverlaps') {
        final not = where['not'] as bool;
        final value = where['value'];
        final path = where['path'] as String?;
        if (path != null) {
          if (value is Expression) {
            parts.add(
              '$boolean${not ? 'not ' : ''}'
              'json_overlaps(json_extract(${wrap(where['column'] as String)}, ?), ${value.sql})',
            );
            bindings.add(path);
          } else {
            parts.add(
              '$boolean${not ? 'not ' : ''}'
              'json_overlaps(json_extract(${wrap(where['column'] as String)}, ?), ?)',
            );
            bindings.add(path);
            bindings.add(jsonEncode(value));
          }
        } else if (value is Expression) {
          parts.add(
            '$boolean${not ? 'not ' : ''}'
            'json_overlaps(${wrap(where['column'] as String)}, ${value.sql})',
          );
        } else {
          parts.add(
            '$boolean${not ? 'not ' : ''}'
            'json_overlaps(${wrap(where['column'] as String)}, ?)',
          );
          bindings.add(jsonEncode(value));
        }
      } else if (type == 'fullText') {
        final columns = (where['columns'] as List<String>).map(wrap).join(', ');
        final options = where['options'] as Map<String, dynamic>;
        final mode = options['mode'] as String?;
        if (mode != null && mode != 'boolean' && mode != 'natural language') {
          throw LaconicException('Invalid MySQL full text mode: "$mode"');
        }
        final expanded = options['expanded'] as bool? ?? false;
        final modeSql =
            mode == 'boolean'
                ? ' in boolean mode'
                : ' in natural language mode';
        final expandedSql =
            expanded && mode != 'boolean' ? ' with query expansion' : '';
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            '${boolean}match ($columns) against ('
            '${value.sql}$modeSql$expandedSql)',
          );
        } else {
          parts.add(
            '${boolean}match ($columns) against (?$modeSql$expandedSql)',
          );
          bindings.add(value);
        }
      } else if (type == 'column') {
        // WHERE column1 = column2
        parts.add(
          '$boolean${wrap(where['first'] as String)} ${where['comparator']} ${wrap(where['second'] as String)}',
        );
      } else if (type == 'in') {
        // WHERE column IN (?, ?, ?) or WHERE column NOT IN (?, ?, ?)
        final column = wrap(where['column'] as String);
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
          '$boolean${wrap(where['column'] as String)} ${not ? 'not in' : 'in'} (${where['sql']})',
        );
        bindings.addAll(where['bindings'] as List<Object?>);
      } else if (type == 'null') {
        parts.add(
          '$boolean${compileNullPredicate(where['column'] as String, where['not'] as bool)}',
        );
      } else if (type == 'between') {
        // WHERE column BETWEEN ? AND ? or WHERE column NOT BETWEEN ? AND ?
        final column = wrap(where['column'] as String);
        final values = where['values'] as List<Object?>;
        final not = where['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add('$boolean$column $betweenKeyword ? and ?');
        bindings.addAll(values);
      } else if (type == 'betweenColumns') {
        // WHERE column BETWEEN column1 AND column2
        final column = wrap(where['column'] as String);
        final betweenColumns =
            (where['betweenColumns'] as List<String>).map(wrap).toList();
        final not = where['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add(
          '$boolean$column $betweenKeyword ${betweenColumns[0]} and ${betweenColumns[1]}',
        );
      } else if (type == 'integerInRaw') {
        final column = wrap(where['column'] as String);
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
        final columns = (where['columns'] as List<String>).map(wrap).join(', ');
        final operator = where['operator'];
        final values = where['values'] as List<Object?>;
        final placeholders = <String>[];
        for (final value in values) {
          if (value is Expression) {
            placeholders.add(value.sql);
          } else {
            placeholders.add('?');
            bindings.add(value);
          }
        }
        parts.add('$boolean($columns) $operator (${placeholders.join(', ')})');
      } else if (type == 'valueBetween') {
        final columns = (where['columns'] as List<String>).map(wrap).toList();
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
            '$boolean${wrap(where['column'] as String)} <=> ${value.sql}',
          );
        } else {
          parts.add('$boolean${wrap(where['column'] as String)} <=> ?');
          bindings.add(value);
        }
      } else if (type == 'all') {
        // WHERE (col1 = ? AND col2 = ? AND col3 = ?)
        final columns = (where['columns'] as List<String>).map(wrap).toList();
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
        final columns = (where['columns'] as List<String>).map(wrap).toList();
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
        final columns = (where['columns'] as List<String>).map(wrap).toList();
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

  /// Returns a complete SQL expression for a date-part extraction.
  /// The returned string already includes the column reference.
  String _dateExpression(String dateType, String column) {
    column = wrap(column);
    switch (dateType) {
      case 'date':
        return 'date($column)';
      case 'time':
        return 'time($column)';
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
        buffer.write(
          '${wrap(order['column'] as String)} ${order['direction']}',
        );
      }
      if (i < orders.length - 1) {
        buffer.write(', ');
      }
    }

    return buffer.toString();
  }

  /// Compiles GROUP BY clauses.
  String _compileGroups(List<Object> groups) {
    return ' group by ${groups.map(wrap).join(', ')}';
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
          '$boolean${wrap(having['column'] as Object)} ${not ? 'is not null' : 'is null'}',
        );
      } else if (having['type'] == 'between') {
        final not = having['not'] as bool;
        parts.add(
          '$boolean${wrap(having['column'] as Object)} ${not ? 'not between' : 'between'} ? and ?',
        );
        bindings.addAll(having['values'] as List<Object?>);
      } else {
        final value = having['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${wrap(having['column'] as Object)} ${having['comparator']} ${value.sql}',
          );
        } else {
          parts.add(
            '$boolean${wrap(having['column'] as Object)} ${having['comparator']} ?',
          );
          bindings.add(value);
        }
      }
    }

    return parts.join('');
  }
}
