import 'package:laconic/src/exception.dart';
import 'package:laconic/src/laconic.dart';
import 'package:laconic/src/query_builder/grammar/grammar.dart';
import 'package:laconic/src/query_builder/grammar/sql_grammar.dart';
import 'package:laconic/src/result.dart';

/// Fluent query builder for constructing and executing database queries.
class QueryBuilder {
  final Laconic _laconic;
  final Grammar _grammar;

  /// The table name for the query.
  final String _table;

  /// The columns to select.
  List<String> _columns = ['*'];

  /// The WHERE conditions.
  final List<Map<String, dynamic>> _wheres = [];

  /// The JOIN clauses.
  final List<Map<String, dynamic>> _joins = [];

  /// The ORDER BY clauses.
  final List<Map<String, dynamic>> _orders = [];

  /// The LIMIT value.
  int? _limit;

  /// The OFFSET value.
  int? _offset;

  /// Creates a new query builder instance.
  QueryBuilder({required Laconic laconic, required String table})
      : _laconic = laconic,
        _table = table,
        _grammar = SqlGrammar();

  /// Returns the count of records matching the query.
  Future<int> count() async {
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: _columns,
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      limit: _limit,
      offset: _offset,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);
    return results.length;
  }

  /// Deletes records matching the query.
  Future<void> delete() async {
    final compiled = _grammar.compileDelete(
      table: _table,
      wheres: _wheres,
    );

    await _laconic.statement(compiled.sql, compiled.bindings);
  }

  /// Returns the first record matching the query.
  ///
  /// Throws [LaconicException] if no record is found.
  Future<LaconicResult> first() async {
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: _columns,
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      limit: _limit,
      offset: _offset,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) {
      throw LaconicException('No record found');
    }

    return results.first;
  }

  /// Returns all records matching the query.
  Future<List<LaconicResult>> get() async {
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: _columns,
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      limit: _limit,
      offset: _offset,
    );

    return await _laconic.select(compiled.sql, compiled.bindings);
  }

  /// Inserts records into the database.
  ///
  /// [data] must be a non-empty list of maps where each map represents a row.
  /// All maps must have the same keys.
  Future<void> insert(List<Map<String, Object?>> data) async {
    if (data.isEmpty) {
      throw LaconicException('Cannot insert an empty list of data');
    }

    final compiled = _grammar.compileInsert(
      table: _table,
      data: data,
    );

    await _laconic.statement(compiled.sql, compiled.bindings);
  }

  /// Adds a JOIN clause to the query.
  ///
  /// [targetTable] is the table to join.
  /// [leftColumn] is the column from the left table.
  /// [rightColumn] is the column from the right table.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.join('posts p', 'u.id', 'p.user_id')
  /// ```
  ///
  /// For multiple join conditions, you can chain multiple calls or use
  /// the closure-based version with [joinAdvanced].
  QueryBuilder join(
    String targetTable,
    String leftColumn,
    String rightColumn, {
    String operator = '=',
  }) {
    _joins.add({
      'table': targetTable,
      'conditions': [
        {
          'left': leftColumn,
          'operator': operator,
          'right': rightColumn,
          'boolean': 'and',
        }
      ],
    });

    return this;
  }

  /// Sets the LIMIT for the query.
  QueryBuilder limit(int limit) {
    _limit = limit;
    return this;
  }

  /// Sets the OFFSET for the query.
  QueryBuilder offset(int offset) {
    _offset = offset;
    return this;
  }

  /// Adds an ORDER BY clause to the query.
  ///
  /// [column] is the column name to order by.
  /// [direction] must be 'asc' or 'desc' (defaults to 'asc').
  QueryBuilder orderBy(String column, {String direction = 'asc'}) {
    _orders.add({
      'column': column,
      'direction': direction,
    });
    return this;
  }

  /// Adds an OR WHERE condition to the query.
  ///
  /// [column] is the column name.
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  QueryBuilder orWhere(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'basic',
      'column': column,
      'operator': comparator,
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Specifies the columns to select.
  ///
  /// If [columns] is null or empty, selects all columns (*).
  QueryBuilder select(List<String>? columns) {
    if (columns == null || columns.isEmpty) {
      _columns = ['*'];
    } else {
      _columns = columns;
    }
    return this;
  }

  /// Returns a single record matching the query.
  ///
  /// Throws [LaconicException] if no record is found.
  Future<LaconicResult> sole() async {
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: _columns,
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      limit: _limit,
      offset: _offset,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) {
      throw LaconicException('No record found');
    }

    return results.first;
  }

  /// Updates records matching the query.
  ///
  /// [data] is a map of column-value pairs to update.
  Future<void> update(Map<String, Object?> data) async {
    final compiled = _grammar.compileUpdate(
      table: _table,
      data: data,
      wheres: _wheres,
    );

    await _laconic.statement(compiled.sql, compiled.bindings);
  }

  /// Adds a WHERE condition to the query.
  ///
  /// [column] is the column name.
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  QueryBuilder where(String column, Object? value, {String comparator = '='}) {
    _wheres.add({
      'type': 'basic',
      'column': column,
      'operator': comparator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }
}
