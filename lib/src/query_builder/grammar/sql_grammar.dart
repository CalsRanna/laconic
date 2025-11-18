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
    int? limit,
    int? offset,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('select ${_compileColumns(columns)}');
    buffer.write(' from $table');

    if (joins.isNotEmpty) {
      buffer.write(_compileJoins(joins, bindings));
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(wheres, bindings));
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

      parts.add('$boolean${condition['left']} ${condition['operator']} ${condition['right']}');
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
        parts.add('$boolean${where['column']} ${where['operator']} ?');
        bindings.add(where['value']);
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
}
