import 'package:laconic/src/query_builder/grammar/compiled_query.dart';
import 'package:laconic/src/query_builder/grammar/grammar.dart';

/// SQL grammar implementation for SQLite and MySQL.
///
/// Since SQLite and MySQL share the same basic SQL syntax for common operations,
/// this single implementation works for both databases.
class SqlGrammar extends Grammar {
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
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('select ');
    if (distinct) {
      buffer.write('distinct ');
    }
    buffer.write(_compileColumns(columns));
    buffer.write(' from $table');

    if (joins.isNotEmpty) {
      buffer.write(_compileJoins(joins, bindings));
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(wheres, bindings));
    }

    if (groups.isNotEmpty) {
      buffer.write(_compileGroups(groups));
    }

    if (havings.isNotEmpty) {
      buffer.write(' having ');
      buffer.write(_compileHavings(havings, bindings));
    }

    if (orders.isNotEmpty) {
      buffer.write(_compileOrders(orders));
    }

    if (limit != null) {
      buffer.write(' limit ?');
      bindings.add(limit);
    }

    if (offset != null) {
      buffer.write(' offset ?');
      bindings.add(offset);
    }

    return CompiledQuery(
      sql: buffer.toString(),
      bindings: bindings,
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

    buffer.write('insert into $table (');
    buffer.write(columns.join(', '));
    buffer.write(') values ');

    for (var i = 0; i < data.length; i++) {
      buffer.write('(');
      final row = data[i];
      for (var j = 0; j < columns.length; j++) {
        buffer.write('?');
        bindings.add(row[columns[j]]);
        if (j < columns.length - 1) {
          buffer.write(', ');
        }
      }
      buffer.write(')');
      if (i < data.length - 1) {
        buffer.write(', ');
      }
    }

    return CompiledQuery(
      sql: buffer.toString(),
      bindings: bindings,
    );
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
      buffer.write('${entries[i].key} = ?');
      bindings.add(entries[i].value);
      if (i < entries.length - 1) {
        buffer.write(', ');
      }
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(wheres, bindings));
    }

    return CompiledQuery(
      sql: buffer.toString(),
      bindings: bindings,
    );
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

    return CompiledQuery(
      sql: buffer.toString(),
      bindings: bindings,
    );
  }

  /// Compiles column names for SELECT clause.
  String _compileColumns(List<String> columns) {
    if (columns.isEmpty || (columns.length == 1 && columns[0] == '*')) {
      return '*';
    }
    return columns.join(', ');
  }

  /// Compiles JOIN clauses.
  String _compileJoins(
    List<Map<String, dynamic>> joins,
    List<Object?> bindings,
  ) {
    final buffer = StringBuffer();

    for (final join in joins) {
      buffer.write(' join ${join['table']} on ');
      buffer.write(_compileJoinConditions(join['conditions'], bindings));
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
      final type = condition['type'] ?? 'on'; // Default to 'on' for backward compatibility

      if (type == 'on') {
        // ON clause: column = column
        parts.add('$boolean${condition['left']} ${condition['operator']} ${condition['right']}');
      } else if (type == 'where') {
        // WHERE clause within JOIN: column = ?
        parts.add('$boolean${condition['column']} ${condition['operator']} ?');
        bindings.add(condition['value']);
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
        // WHERE column = ?
        parts.add('$boolean${where['column']} ${where['operator']} ?');
        bindings.add(where['value']);
      } else if (type == 'column') {
        // WHERE column1 = column2
        parts.add('$boolean${where['first']} ${where['operator']} ${where['second']}');
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
        parts.add('$boolean$column $betweenKeyword ${betweenColumns[0]} and ${betweenColumns[1]}');
      } else if (type == 'all') {
        // WHERE (col1 = ? AND col2 = ? AND col3 = ?)
        final columns = where['columns'] as List<String>;
        final operator = where['operator'];
        final value = where['value'];
        final conditions = columns.map((col) => '$col $operator ?').join(' and ');
        parts.add('$boolean($conditions)');
        for (var j = 0; j < columns.length; j++) {
          bindings.add(value);
        }
      } else if (type == 'any') {
        // WHERE (col1 = ? OR col2 = ? OR col3 = ?)
        final columns = where['columns'] as List<String>;
        final operator = where['operator'];
        final value = where['value'];
        final conditions = columns.map((col) => '$col $operator ?').join(' or ');
        parts.add('$boolean($conditions)');
        for (var j = 0; j < columns.length; j++) {
          bindings.add(value);
        }
      } else if (type == 'none') {
        // WHERE NOT (col1 = ? OR col2 = ? OR col3 = ?)
        final columns = where['columns'] as List<String>;
        final operator = where['operator'];
        final value = where['value'];
        final conditions = columns.map((col) => '$col $operator ?').join(' or ');
        parts.add('${boolean}not ($conditions)');
        for (var j = 0; j < columns.length; j++) {
          bindings.add(value);
        }
      } else if (type == 'nested') {
        final nested = _compileWheres(where['conditions'], bindings);
        parts.add('$boolean($nested)');
      }
    }

    return parts.join('');
  }

  /// Compiles ORDER BY clauses.
  String _compileOrders(List<Map<String, dynamic>> orders) {
    final buffer = StringBuffer();
    buffer.write(' order by ');

    for (var i = 0; i < orders.length; i++) {
      buffer.write('${orders[i]['column']} ${orders[i]['direction']}');
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
      parts.add('$boolean${having['column']} ${having['operator']} ?');
      bindings.add(having['value']);
    }

    return parts.join('');
  }
}
