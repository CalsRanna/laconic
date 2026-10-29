import 'dart:convert';

import 'package:laconic/laconic.dart';
import 'postgresql_placeholders.dart';

part 'postgresql_schema.dart';

/// PostgreSQL-specific SQL grammar.
///
/// Handles PostgreSQL-specific syntax differences:
/// - Positional parameters ($1, $2, etc.)
/// - RETURNING clause for insertGetId
class PostgresqlGrammar extends SqlGrammar with _PostgresqlSchema {
  String _jsonSelector(String column, String path, {bool text = true}) {
    final segments = jsonPathSegments(
      path,
    ).map((part) => compileSchemaLiteral('$part')).join(', ');
    return 'jsonb_extract_path${text ? '_text' : ''}((${wrap(column)})::jsonb, $segments)';
  }

  @override
  String compileJsonSelector(String column, String path) =>
      _jsonSelector(column, path);

  @override
  String compileBasicPredicate(
    String column,
    String comparator,
    Object? value,
    List<Object?> bindings,
  ) {
    if (column.contains('->') &&
        value is! String &&
        value is! Expression &&
        value != null) {
      final selector = splitJsonSelector(column);
      return '${_jsonSelector(selector.column, selector.path, text: false)} $comparator ${parameter(jsonEncode(value), bindings)}::jsonb';
    }
    return super.compileBasicPredicate(column, comparator, value, bindings);
  }

  @override
  String compileJsonUpdate(
    String source,
    String path,
    Object? value,
    List<Object?> bindings,
  ) {
    final segments = jsonPathSegments(
      path,
    ).map((part) => compileSchemaLiteral('$part')).join(', ');
    final sqlValue =
        value is Expression
            ? value.sql
            : parameter(jsonEncode(value), bindings);
    return 'jsonb_set(($source)::jsonb, array[$segments]::text[], ($sqlValue)::jsonb)';
  }

  @override
  bool get numberedPlaceholders => true;

  @override
  String inlineSubquery(CompiledQuery query) =>
      PostgresqlPlaceholders.toQuestionPlaceholders(query.sql);

  @override
  CompiledQuery compileInlineSubquery(CompiledQuery query) {
    final bindings = <Object?>[];
    final sql = PostgresqlPlaceholders.toQuestionPlaceholders(
      query.sql,
      onParameter: (index) => bindings.add(query.bindings[index - 1]),
    );
    return CompiledQuery(sql: sql, bindings: bindings);
  }

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
      if (distinctColumns != null && distinctColumns.isNotEmpty) {
        buffer.write('distinct on (${distinctColumns.map(wrap).join(', ')}) ');
      } else {
        buffer.write('distinct ');
      }
    }
    final compiledColumns = PostgresqlPlaceholders.compile(
      _compileColumns(columns),
      selectBindings,
      offset: bindings.length,
    );
    buffer.write(compiledColumns.sql);
    bindings.addAll(compiledColumns.bindings);
    if (fromSubquery != null) {
      final embedded = PostgresqlPlaceholders.compile(
        fromSubquery.sql,
        fromSubquery.bindings,
        offset: bindings.length,
      );
      if (fromAlias != null) {
        buffer.write(
          ' from (${embedded.sql}) as ${quoteSchemaIdentifier(fromAlias)}',
        );
      } else {
        buffer.write(' from ${embedded.sql}');
      }
      bindings.addAll(embedded.bindings);
    } else {
      buffer.write(' from ${wrapTable(table)}');
    }

    if (joins.isNotEmpty) {
      buffer.write(_compileJoins(joins, bindings));
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(wheres, bindings));
    }

    if (groups.isNotEmpty) {
      final compiledGroups = PostgresqlPlaceholders.compile(
        _compileGroups(groups),
        groupBindings,
        offset: bindings.length,
      );
      buffer.write(compiledGroups.sql);
      bindings.addAll(compiledGroups.bindings);
    }

    if (havings.isNotEmpty) {
      buffer.write(' having ');
      buffer.write(_compileHavings(havings, bindings));
    }

    if (orders.isNotEmpty) {
      buffer.write(_compileOrders(orders, bindings));
    }

    if (limit != null) {
      buffer.write(' limit \$${bindings.length + 1}');
      bindings.add(limit);
    }

    if (offset != null) {
      buffer.write(' offset \$${bindings.length + 1}');
      bindings.add(offset);
    }

    for (final lock in locks) {
      if (lock['type'] == 'for_update') {
        buffer.write(' for update');
      } else if (lock['type'] == 'for_share') {
        buffer.write(' for share');
      } else if (lock['type'] == 'raw') {
        buffer.write(' ${lock['value']}');
      }
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileUnion({
    required List<CompiledQuery> queries,
    required List<bool> all,
    required List<Object> columns,
    required List<Map<String, dynamic>> orders,
    List<Map<String, dynamic>> wheres = const [],
    int? limit,
    int? offset,
    List<Map<String, dynamic>> locks = const [],
  }) {
    final sql = StringBuffer();
    final bindings = <Object?>[];
    for (var i = 0; i < queries.length; i++) {
      if (i > 0) sql.write(all[i - 1] ? ' union all ' : ' union ');
      final branch = PostgresqlPlaceholders.compile(
        queries[i].sql,
        queries[i].bindings,
        offset: bindings.length,
      );
      sql.write('select * from (${branch.sql}) as laconic_branch_$i');
      bindings.addAll(branch.bindings);
    }
    final outer = compileSelect(
      table: 'laconic_union',
      columns: columns,
      wheres: wheres,
      joins: [],
      orders: orders,
      groups: [],
      havings: [],
      distinct: false,
      limit: limit,
      offset: offset,
      locks: locks,
    );
    final shifted = PostgresqlPlaceholders.compile(
      outer.sql,
      outer.bindings,
      offset: bindings.length,
    );
    return CompiledQuery(
      sql: shifted.sql.replaceFirst(
        'from ${wrapTable('laconic_union')}',
        'from ($sql) as laconic_union',
      ),
      bindings: [...bindings, ...outer.bindings],
    );
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
        if (value is Expression) {
          buffer.write(value.sql);
        } else {
          buffer.write('\$${bindings.length + 1}');
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
  CompiledQuery compileInsertGetId({
    required String table,
    required Map<String, Object?> data,
    String idColumn = 'id',
  }) {
    final compiled = compileInsert(table: table, data: [data]);
    // Add RETURNING clause for PostgreSQL
    return CompiledQuery(
      sql: '${compiled.sql} returning ${wrap(idColumn)}',
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

    buffer.write(
      'update ${wrapTable(table)} set ${wrap(column)} = ${wrap(column)} + \$${bindings.length + 1}',
    );
    bindings.add(amount);

    if (extra != null && extra.isNotEmpty) {
      for (final entry in extra.entries) {
        final value = entry.value;
        if (value is Expression) {
          buffer.write(', ${wrap(entry.key)} = ${value.sql}');
        } else {
          buffer.write(', ${wrap(entry.key)} = \$${bindings.length + 1}');
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
      'update ${wrapTable(table)} set ${wrap(column)} = ${wrap(column)} - \$${bindings.length + 1}',
    );
    bindings.add(amount);

    if (extra != null && extra.isNotEmpty) {
      for (final entry in extra.entries) {
        final value = entry.value;
        if (value is Expression) {
          buffer.write(', ${wrap(entry.key)} = ${value.sql}');
        } else {
          buffer.write(', ${wrap(entry.key)} = \$${bindings.length + 1}');
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
    final assignments = compileAssignments(data, bindings);
    final sql = StringBuffer('update ${wrapTable(table)} set $assignments');
    final scope = _compileWriteScope(
      table,
      wheres,
      joins,
      orders,
      limit,
      offset,
      bindings,
    );
    if (scope.isNotEmpty) sql.write(' where $scope');
    return CompiledQuery(sql: sql.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileUpdateFrom({
    required String table,
    required String from,
    required Map<String, Object?> data,
    required List<Map<String, dynamic>> wheres,
  }) {
    final bindings = <Object?>[];
    final assignments = compileAssignments(data, bindings);
    final sql = StringBuffer(
      'update ${wrapTable(table)} set $assignments from ${wrapTable(from)}',
    );
    if (wheres.isNotEmpty) {
      sql.write(' where ${_compileWheres(wheres, bindings)}');
    }
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
    final sql = StringBuffer('delete from ${wrapTable(table)}');
    final scope = _compileWriteScope(
      table,
      wheres,
      joins,
      orders,
      limit,
      offset,
      bindings,
    );
    if (scope.isNotEmpty) sql.write(' where $scope');
    return CompiledQuery(sql: sql.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileTruncate({required String table}) {
    return CompiledQuery(
      sql: 'truncate table ${wrapTable(table)} restart identity',
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
      sql: '${compiled.sql} on conflict do nothing',
      bindings: compiled.bindings,
    );
  }

  @override
  String compileInsertOrIgnoreUsing({
    required String table,
    required List<String> columns,
    required String sql,
  }) {
    return 'insert into ${wrapTable(table)} (${columns.map(wrap).join(', ')}) $sql '
        'on conflict do nothing';
  }

  @override
  CompiledQuery compileUpsert({
    required String table,
    required List<Map<String, Object?>> data,
    required List<String> uniqueBy,
    List<String>? update,
  }) {
    final compiled = compileInsert(table: table, data: data);
    final conflictCols = uniqueBy.map(wrap).join(', ');
    final updateCols =
        update ?? data.first.keys.where((k) => !uniqueBy.contains(k)).toList();
    if (updateCols.isEmpty) {
      return CompiledQuery(
        sql: '${compiled.sql} on conflict($conflictCols) do nothing',
        bindings: compiled.bindings,
      );
    }
    final setClauses = updateCols
        .map((c) => '${wrap(c)} = excluded.${wrap(c)}')
        .join(', ');
    return CompiledQuery(
      sql:
          '${compiled.sql} on conflict($conflictCols) do update set $setClauses',
      bindings: compiled.bindings,
    );
  }

  String _compileWriteScope(
    String table,
    List<Map<String, dynamic>> wheres,
    List<Map<String, dynamic>> joins,
    List<Map<String, dynamic>> orders,
    int? limit,
    int? offset,
    List<Object?> bindings,
  ) {
    if (joins.isEmpty && orders.isEmpty && limit == null && offset == null) {
      return _compileWheres(wheres, bindings);
    }
    final identity =
        '(${tableReference(table)}.tableoid, ${tableReference(table)}.ctid)';
    final query = compileSelect(
      table: table,
      columns: [
        Expression('${tableReference(table)}.tableoid'),
        Expression('${tableReference(table)}.ctid'),
      ],
      wheres: wheres,
      joins: joins,
      orders: orders,
      groups: [],
      havings: [],
      distinct: false,
      limit: limit,
      offset: offset,
    );
    final embedded = PostgresqlPlaceholders.compile(
      query.sql,
      query.bindings,
      offset: bindings.length,
    );
    bindings.addAll(embedded.bindings);
    return '$identity in (${embedded.sql})';
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
      var tableSql = table;
      if (tableBindings != null) {
        final embedded = PostgresqlPlaceholders.compile(
          tableSql,
          tableBindings,
          offset: bindings.length,
        );
        tableSql = embedded.sql;
        bindings.addAll(embedded.bindings);
      }

      if (type == 'lateral') {
        final joinType = join['joinType'] as String? ?? 'inner';
        buffer.write(' $joinType join lateral $tableSql on true');
        continue;
      }

      switch (type) {
        case 'left':
          buffer.write(' left join $tableSql');
        case 'right':
          buffer.write(' right join $tableSql');
        case 'cross':
          buffer.write(' cross join $tableSql');
        case 'straight':
          buffer.write(' join $tableSql');
        case 'inner':
        default:
          buffer.write(' join $tableSql');
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
      final type = condition['type'] ?? 'on';

      if (type == 'on') {
        // ON clause: column = column
        parts.add(
          '$boolean${wrap(condition['left'] as String)} '
          '${condition['comparator']} '
          '${wrap(condition['right'] as String)}',
        );
      } else if (type == 'where') {
        parts.add(
          '$boolean${compileBasicPredicate(condition['column'] as String, condition['comparator'] as String, condition['value'], bindings)}',
        );
      } else if (type == 'column') {
        // WHERE column1 = column2
        parts.add(
          '$boolean${wrap(condition['first'] as String)} '
          '${condition['comparator']} '
          '${wrap(condition['second'] as String)}',
        );
      } else if (type == 'null') {
        parts.add(
          '$boolean${compileNullPredicate(condition['column'] as String, condition['not'] as bool)}',
        );
      } else if (type == 'in') {
        // WHERE column IN ($1, $2, $3) or WHERE column NOT IN ($1, $2, $3)
        final column = wrap(condition['column'] as String);
        final values = condition['values'] as List<Object?>;
        final not = condition['not'] as bool;
        final inKeyword = not ? 'not in' : 'in';

        if (values.isEmpty) {
          // Handle empty IN clause - always false for IN, always true for NOT IN
          parts.add('$boolean${not ? '1 = 1' : '1 = 0'}');
        } else {
          final placeholders = List.generate(
            values.length,
            (i) => '\$${bindings.length + i + 1}',
          ).join(', ');
          parts.add('$boolean$column $inKeyword ($placeholders)');
          bindings.addAll(values);
        }
      } else if (type == 'between') {
        // WHERE column BETWEEN $1 AND $2 or WHERE column NOT BETWEEN $1 AND $2
        final column = wrap(condition['column'] as String);
        final values = condition['values'] as List<Object?>;
        final not = condition['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add(
          '$boolean$column $betweenKeyword \$${bindings.length + 1} and \$${bindings.length + 2}',
        );
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
        final convertedSql = _compileRawSql(
          condition['sql'],
          condition['bindings'] as List<Object?>,
          bindings,
        );
        parts.add('$boolean($convertedSql)');
      } else if (type == 'exists') {
        final not = condition['not'] as bool;
        final keyword = not ? 'not exists' : 'exists';
        final subSql = condition['sql'] as String;
        final subBindings = condition['bindings'] as List<Object?>;
        final offsetSql =
            PostgresqlPlaceholders.compile(
              subSql,
              subBindings,
              offset: bindings.length,
            ).sql;
        bindings.addAll(subBindings);
        parts.add('$boolean$keyword ($offsetSql)');
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
        final keyword = not ? 'not ilike' : 'ilike';
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${wrap(where['column'] as String)} $keyword ${value.sql}',
          );
        } else {
          parts.add(
            '$boolean${wrap(where['column'] as String)} $keyword \$${bindings.length + 1}',
          );
          bindings.add(value);
        }
      } else if (type == 'subquery') {
        final subSql = where['sql'] as String;
        final subBindings = where['bindings'] as List<Object?>;
        final embedded = PostgresqlPlaceholders.compile(
          subSql,
          subBindings,
          offset: bindings.length,
        );
        parts.add(
          '$boolean${wrap(where['column'] as String)} ${where['comparator']} (${embedded.sql})',
        );
        bindings.addAll(embedded.bindings);
      } else if (type == 'binary') {
        throw LaconicException(
          'PostgreSQL does not support binary comparison operations',
        );
      } else if (type == 'jsonContains') {
        final not = where['not'] as bool;
        final value = where['value'];
        final path = where['path'] as String?;
        String target;
        if (path == null || path == r'$') {
          target = '(${wrap(where['column'] as String)})::jsonb';
        } else {
          final segments = _jsonPathSegments(path);
          final placeholders = <String>[];
          for (final segment in segments) {
            placeholders.add('\$${bindings.length + 1}');
            bindings.add(segment);
          }
          target =
              placeholders.isEmpty
                  ? '(${wrap(where['column'] as String)})::jsonb'
                  : 'jsonb_extract_path((${wrap(where['column'] as String)})::jsonb, '
                      '${placeholders.join(', ')})';
        }
        if (value is Expression) {
          parts.add(
            '$boolean${not ? 'not ' : ''}'
            '($target @> (${value.sql})::jsonb)',
          );
        } else {
          parts.add(
            '$boolean${not ? 'not ' : ''}'
            '($target @> \$${bindings.length + 1}::jsonb)',
          );
          bindings.add(jsonEncode(value));
        }
      } else if (type == 'jsonContainsKey') {
        final not = where['not'] as bool;
        final segments = _jsonPathSegments(where['path'] as String);
        final placeholders = <String>[];
        for (final segment in segments) {
          placeholders.add('\$${bindings.length + 1}');
          bindings.add(segment);
        }
        final expression =
            placeholders.isEmpty
                ? '(${wrap(where['column'] as String)})::jsonb is not null'
                : 'jsonb_extract_path((${wrap(where['column'] as String)})::jsonb, '
                    '${placeholders.join(', ')}) is not null';
        parts.add('$boolean${not ? 'not ' : ''}($expression)');
      } else if (type == 'jsonLength') {
        final path = where['path'] as String?;
        final comparator = where['comparator'];
        String target;
        if (path == null || path == r'$') {
          target =
              'jsonb_array_length((${wrap(where['column'] as String)})::jsonb)';
        } else {
          final segments = _jsonPathSegments(path);
          final placeholders = <String>[];
          for (final segment in segments) {
            placeholders.add('\$${bindings.length + 1}');
            bindings.add(segment);
          }
          target =
              'jsonb_array_length(jsonb_extract_path('
              '(${wrap(where['column'] as String)})::jsonb, ${placeholders.join(', ')}))';
        }
        parts.add('$boolean$target $comparator \$${bindings.length + 1}');
        bindings.add(where['value']);
      } else if (type == 'jsonOverlaps') {
        final not = where['not'] as bool;
        final value = where['value'];
        if (value is! List) {
          throw LaconicException('JSON overlaps requires a list of values');
        }
        if (value.isEmpty) {
          parts.add('$boolean${not ? '1 = 1' : '1 = 0'}');
          continue;
        }
        final path = where['path'] as String?;
        String target;
        if (path == null || path == r'$') {
          target = '(${wrap(where['column'] as String)})::jsonb';
        } else {
          final segments = _jsonPathSegments(path);
          final placeholders = <String>[];
          for (final segment in segments) {
            placeholders.add('\$${bindings.length + 1}');
            bindings.add(segment);
          }
          target =
              placeholders.isEmpty
                  ? '(${wrap(where['column'] as String)})::jsonb'
                  : 'jsonb_extract_path((${wrap(where['column'] as String)})::jsonb, '
                      '${placeholders.join(', ')})';
        }
        parts.add(
          '$boolean${not ? 'not ' : ''}'
          '(case when $target is null then null else exists ('
          'select 1 from jsonb_array_elements($target) as laconic_json_element(value) '
          'join jsonb_array_elements(\$${bindings.length + 1}::jsonb) '
          'as laconic_json_candidate(value) '
          'on laconic_json_element.value = laconic_json_candidate.value'
          ') end)',
        );
        bindings.add(jsonEncode(value));
      } else if (type == 'fullText') {
        final columns = (where['columns'] as List<String>).map(wrap).toList();
        final options = where['options'] as Map<String, dynamic>;
        final language = options['language'] as String? ?? 'english';
        if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(language)) {
          throw LaconicException('Invalid full text language: "$language"');
        }
        final mode = options['mode'] as String? ?? 'plain';
        final queryFunction = switch (mode) {
          'plain' => 'plainto_tsquery',
          'phrase' => 'phraseto_tsquery',
          'websearch' => 'websearch_to_tsquery',
          'raw' => 'to_tsquery',
          _ =>
            throw LaconicException(
              'Invalid PostgreSQL full text mode: "$mode"',
            ),
        };
        final vector = columns
            .map((column) => "to_tsvector('$language', coalesce($column, ''))")
            .join(' || ');
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            "$boolean($vector) @@ $queryFunction('$language', ${value.sql})",
          );
        } else {
          parts.add(
            "$boolean($vector) @@ $queryFunction('$language', "
            '\$${bindings.length + 1})',
          );
          bindings.add(value);
        }
      } else if (type == 'column') {
        // WHERE column1 = column2
        parts.add(
          '$boolean${wrap(where['first'] as String)} '
          '${where['comparator']} '
          '${wrap(where['second'] as String)}',
        );
      } else if (type == 'in') {
        // WHERE column IN ($1, $2, $3) or WHERE column NOT IN ($1, $2, $3)
        final column = wrap(where['column'] as String);
        final values = where['values'] as List<Object?>;
        final not = where['not'] as bool;
        final inKeyword = not ? 'not in' : 'in';

        if (values.isEmpty) {
          // Handle empty IN clause - always false for IN, always true for NOT IN
          parts.add('$boolean${not ? '1 = 1' : '1 = 0'}');
        } else {
          final placeholders = List.generate(
            values.length,
            (i) => '\$${bindings.length + i + 1}',
          ).join(', ');
          parts.add('$boolean$column $inKeyword ($placeholders)');
          bindings.addAll(values);
        }
      } else if (type == 'inSubquery') {
        final not = where['not'] as bool;
        final subSql = where['sql'] as String;
        final subBindings = where['bindings'] as List<Object?>;
        final embedded = PostgresqlPlaceholders.compile(
          subSql,
          subBindings,
          offset: bindings.length,
        );
        parts.add(
          '$boolean${wrap(where['column'] as String)} ${not ? 'not in' : 'in'} (${embedded.sql})',
        );
        bindings.addAll(embedded.bindings);
      } else if (type == 'null') {
        parts.add(
          '$boolean${compileNullPredicate(where['column'] as String, where['not'] as bool)}',
        );
      } else if (type == 'between') {
        // WHERE column BETWEEN $1 AND $2 or WHERE column NOT BETWEEN $1 AND $2
        final column = wrap(where['column'] as String);
        final values = where['values'] as List<Object?>;
        final not = where['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add(
          '$boolean$column $betweenKeyword \$${bindings.length + 1} and \$${bindings.length + 2}',
        );
        bindings.addAll(values);
      } else if (type == 'betweenColumns') {
        // WHERE column BETWEEN column1 AND column2
        final column = wrap(where['column'] as String);
        final betweenColumns =
            (where['betweenColumns'] as List<String>).map(wrap).toList();
        final not = where['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add(
          '$boolean$column $betweenKeyword '
          '${betweenColumns[0]} and '
          '${betweenColumns[1]}',
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
            placeholders.add('\$${bindings.length + 1}');
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
          parts.add(
            '$boolean\$${bindings.length + 1} $keyword '
            '${columns[0]} and ${columns[1]}',
          );
          bindings.add(value);
        }
      } else if (type == 'nullSafeEquals') {
        final value = where['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${wrap(where['column'] as String)} is not distinct from ${value.sql}',
          );
        } else {
          parts.add(
            '$boolean${wrap(where['column'] as String)} is not distinct from '
            '\$${bindings.length + 1}',
          );
          bindings.add(value);
        }
      } else if (type == 'all') {
        // WHERE (col1 = $1 AND col2 = $2 AND col3 = $3)
        final columns = (where['columns'] as List<String>).map(wrap).toList();
        final comparator = where['comparator'];
        final value = where['value'];
        final conditions = <String>[];
        for (var j = 0; j < columns.length; j++) {
          conditions.add('${columns[j]} $comparator \$${bindings.length + 1}');
          bindings.add(value);
        }
        parts.add('$boolean(${conditions.join(' and ')})');
      } else if (type == 'any') {
        // WHERE (col1 = $1 OR col2 = $2 OR col3 = $3)
        final columns = (where['columns'] as List<String>).map(wrap).toList();
        final comparator = where['comparator'];
        final value = where['value'];
        final conditions = <String>[];
        for (var j = 0; j < columns.length; j++) {
          conditions.add('${columns[j]} $comparator \$${bindings.length + 1}');
          bindings.add(value);
        }
        parts.add('$boolean(${conditions.join(' or ')})');
      } else if (type == 'none') {
        // WHERE NOT (col1 = $1 OR col2 = $2 OR col3 = $3)
        final columns = (where['columns'] as List<String>).map(wrap).toList();
        final comparator = where['comparator'];
        final value = where['value'];
        final conditions = <String>[];
        for (var j = 0; j < columns.length; j++) {
          conditions.add('${columns[j]} $comparator \$${bindings.length + 1}');
          bindings.add(value);
        }
        parts.add('${boolean}not (${conditions.join(' or ')})');
      } else if (type == 'nested') {
        final nested = _compileWheres(where['conditions'], bindings);
        final not = where['not'] as bool? ?? false;
        parts.add('$boolean${not ? 'not ' : ''}($nested)');
      } else if (type == 'raw') {
        final convertedSql = _compileRawSql(
          where['sql'],
          where['bindings'] as List<Object?>,
          bindings,
        );
        parts.add('$boolean($convertedSql)');
      } else if (type == 'exists') {
        final not = where['not'] as bool;
        final keyword = not ? 'not exists' : 'exists';
        final subSql = where['sql'] as String;
        final subBindings = where['bindings'] as List<Object?>;
        final offsetSql =
            PostgresqlPlaceholders.compile(
              subSql,
              subBindings,
              offset: bindings.length,
            ).sql;
        bindings.addAll(subBindings);
        parts.add('$boolean$keyword ($offsetSql)');
      } else if (type == 'date') {
        final expr = _dateExpression(
          where['dateType'] as String,
          where['column'] as String,
        );
        parts.add(
          '$boolean$expr ${where['comparator'] ?? '='} \$${bindings.length + 1}',
        );
        bindings.add(where['value']);
      }
    }

    return parts.join('');
  }

  List<String> _jsonPathSegments(String path) =>
      jsonPathSegments(path).map((part) => '$part').toList();

  /// Returns a complete SQL expression for a date-part extraction.
  /// The returned string already includes the column reference.
  String _dateExpression(String dateType, String column) {
    column = wrap(column);
    switch (dateType) {
      case 'date':
        return 'date($column)';
      case 'time':
        return '$column::time';
      case 'day':
        return 'extract(day from $column)';
      case 'month':
        return 'extract(month from $column)';
      case 'year':
        return 'extract(year from $column)';
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
        final convertedSql = _compileRawSql(
          order['sql'],
          order['bindings'] as List<Object?>,
          bindings,
        );
        buffer.write(convertedSql);
      } else {
        buffer.write(
          '${wrap(order['column'] as String)} '
          '${order['direction']}',
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
        final convertedSql = _compileRawSql(
          having['sql'],
          having['bindings'] as List<Object?>,
          bindings,
        );
        parts.add('$boolean($convertedSql)');
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
          '$boolean${wrap(having['column'] as Object)} ${not ? 'not between' : 'between'} '
          '\$${bindings.length + 1} and \$${bindings.length + 2}',
        );
        bindings.addAll(having['values'] as List<Object?>);
      } else {
        final value = having['value'];
        if (value is Expression) {
          parts.add(
            '$boolean${wrap(having['column'] as Object)} '
            '${having['comparator']} ${value.sql}',
          );
        } else {
          parts.add(
            '$boolean${wrap(having['column'] as Object)} '
            '${having['comparator']} \$${bindings.length + 1}',
          );
          bindings.add(value);
        }
      }
    }

    return parts.join('');
  }

  String _compileRawSql(
    String rawSql,
    List<Object?> rawBindings,
    List<Object?> bindings,
  ) {
    final compiled = PostgresqlPlaceholders.compile(
      rawSql,
      rawBindings,
      offset: bindings.length,
    );
    bindings.addAll(rawBindings);
    return compiled.sql;
  }
}
