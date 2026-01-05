import 'package:laconic/src/driver.dart';
import 'package:laconic/src/exception.dart';
import 'package:laconic/src/laconic.dart';
import 'package:laconic/src/query_builder/grammar/grammar.dart';
import 'package:laconic/src/query_builder/grammar/postgresql_grammar.dart';
import 'package:laconic/src/query_builder/grammar/sql_grammar.dart';
import 'package:laconic/src/query_builder/join_clause.dart';
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

  /// The GROUP BY columns.
  final List<String> _groups = [];

  /// The HAVING conditions.
  final List<Map<String, dynamic>> _havings = [];

  /// Whether to select distinct records.
  bool _distinct = false;

  /// The LIMIT value.
  int? _limit;

  /// The OFFSET value.
  int? _offset;

  /// Creates a new query builder instance.
  QueryBuilder({required Laconic laconic, required String table})
    : _laconic = laconic,
      _table = table,
      _grammar = _selectGrammar(laconic.driver);

  /// Selects the appropriate Grammar based on the database driver.
  static Grammar _selectGrammar(LaconicDriver driver) {
    switch (driver) {
      case LaconicDriver.mysql:
      case LaconicDriver.sqlite:
        return SqlGrammar();
      case LaconicDriver.postgresql:
        return PostgresqlGrammar();
    }
  }

  /// Returns the count of records matching the query.
  Future<int> count() async {
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: _columns,
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      groups: _groups,
      havings: _havings,
      distinct: _distinct,
      limit: _limit,
      offset: _offset,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);
    return results.length;
  }

  /// Deletes records matching the query.
  Future<void> delete() async {
    final compiled = _grammar.compileDelete(table: _table, wheres: _wheres);

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
      groups: _groups,
      havings: _havings,
      distinct: _distinct,
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
      groups: _groups,
      havings: _havings,
      distinct: _distinct,
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

    final compiled = _grammar.compileInsert(table: _table, data: data);

    await _laconic.statement(compiled.sql, compiled.bindings);
  }

  /// Inserts a single record and returns the auto-increment ID.
  ///
  /// [data] must be a map representing a single row.
  ///
  /// Example:
  /// ```dart
  /// final id = await query.insertGetId({'email': 'john@example.com', 'votes': 0})
  /// ```
  Future<int> insertGetId(Map<String, Object?> data) async {
    final compiled = _grammar.compileInsertGetId(table: _table, data: data);

    return await _laconic.insertAndGetId(compiled.sql, compiled.bindings);
  }

  /// Adds an INNER JOIN clause to the query.
  ///
  /// [targetTable] is the table to join.
  /// [builder] is a function that receives a [JoinClause] to define join conditions.
  ///
  /// The [JoinClause] allows building complex join conditions with multiple ON clauses.
  /// This design mirrors Laravel's approach and allows for:
  /// - Multiple ON conditions with AND/OR
  /// - WHERE conditions within JOINs
  /// - Complex nested conditions
  ///
  /// Example:
  /// ```dart
  /// query.join('posts p', (join) => join.on('u.id', 'p.user_id'))
  /// ```
  ///
  /// Advanced usage (Laravel-compatible):
  /// ```dart
  /// query.join('contacts c', (join) {
  ///   join.on('u.id', 'c.user_id')
  ///       .orOn('u.email', 'c.email')
  ///       .where('c.active', true);
  /// })
  /// ```
  QueryBuilder join(String targetTable, void Function(JoinClause) builder) {
    final joinClause = JoinClause();
    builder(joinClause);

    _joins.add({
      'type': 'inner',
      'table': targetTable,
      'conditions': joinClause.conditions,
    });

    return this;
  }

  /// Adds a LEFT JOIN clause to the query.
  ///
  /// [targetTable] is the table to join.
  /// [builder] is a function that receives a [JoinClause] to define join conditions.
  ///
  /// A LEFT JOIN returns all records from the left table and the matched records
  /// from the right table. If there is no match, the right side will contain NULL values.
  ///
  /// Example:
  /// ```dart
  /// query.leftJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
  /// ```
  QueryBuilder leftJoin(String targetTable, void Function(JoinClause) builder) {
    final joinClause = JoinClause();
    builder(joinClause);

    _joins.add({
      'type': 'left',
      'table': targetTable,
      'conditions': joinClause.conditions,
    });

    return this;
  }

  /// Adds a RIGHT JOIN clause to the query.
  ///
  /// [targetTable] is the table to join.
  /// [builder] is a function that receives a [JoinClause] to define join conditions.
  ///
  /// A RIGHT JOIN returns all records from the right table and the matched records
  /// from the left table. If there is no match, the left side will contain NULL values.
  ///
  /// Note: SQLite does not support RIGHT JOIN natively. Consider using LEFT JOIN instead.
  ///
  /// Example:
  /// ```dart
  /// query.rightJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
  /// ```
  QueryBuilder rightJoin(
    String targetTable,
    void Function(JoinClause) builder,
  ) {
    final joinClause = JoinClause();
    builder(joinClause);

    _joins.add({
      'type': 'right',
      'table': targetTable,
      'conditions': joinClause.conditions,
    });

    return this;
  }

  /// Adds a CROSS JOIN clause to the query.
  ///
  /// [targetTable] is the table to cross join.
  ///
  /// A CROSS JOIN returns the Cartesian product of rows from both tables.
  /// Each row from the first table is combined with all rows from the second table.
  ///
  /// Example:
  /// ```dart
  /// query.crossJoin('colors')
  /// ```
  QueryBuilder crossJoin(String targetTable) {
    _joins.add({
      'type': 'cross',
      'table': targetTable,
      'conditions': <Map<String, dynamic>>[],
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
    _orders.add({'column': column, 'direction': direction});
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

  /// Adds additional columns to the select clause.
  ///
  /// [columns] are the column names to add.
  ///
  /// Example:
  /// ```dart
  /// query.select(['name']).addSelect(['email', 'age'])
  /// ```
  QueryBuilder addSelect(List<String> columns) {
    if (_columns.contains('*')) {
      _columns = columns;
    } else {
      _columns.addAll(columns);
    }
    return this;
  }

  /// Conditionally applies query constraints.
  ///
  /// [condition] determines whether [callback] or [otherwise] is executed.
  /// [callback] is executed if [condition] is true.
  /// [otherwise] is optionally executed if [condition] is false.
  ///
  /// Example:
  /// ```dart
  /// query.when(role != null, (q) => q.where('role_id', role))
  /// query.when(
  ///   sortByVotes,
  ///   (q) => q.orderBy('votes'),
  ///   otherwise: (q) => q.orderBy('name'),
  /// )
  /// ```
  QueryBuilder when(
    bool condition,
    void Function(QueryBuilder) callback, {
    void Function(QueryBuilder)? otherwise,
  }) {
    if (condition) {
      callback(this);
    } else if (otherwise != null) {
      otherwise(this);
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
      groups: _groups,
      havings: _havings,
      distinct: _distinct,
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

  /// Adds a WHERE clause comparing two columns.
  ///
  /// [first] is the first column name.
  /// [second] is the second column name.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.whereColumn('first_name', 'last_name')
  /// query.whereColumn('updated_at', 'created_at', operator: '>')
  /// ```
  QueryBuilder whereColumn(
    String first,
    String second, {
    String operator = '=',
  }) {
    _wheres.add({
      'type': 'column',
      'first': first,
      'operator': operator,
      'second': second,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds a WHERE clause where all columns must match the given value.
  ///
  /// [columns] is the list of column names.
  /// [value] is the value to compare.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.whereAll(['title', 'content'], '%Laravel%', operator: 'like')
  /// ```
  QueryBuilder whereAll(
    List<String> columns,
    Object? value, {
    String operator = '=',
  }) {
    _wheres.add({
      'type': 'all',
      'columns': columns,
      'operator': operator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds a WHERE clause where any column can match the given value.
  ///
  /// [columns] is the list of column names.
  /// [value] is the value to compare.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.whereAny(['name', 'email', 'phone'], 'Example%', operator: 'like')
  /// ```
  QueryBuilder whereAny(
    List<String> columns,
    Object? value, {
    String operator = '=',
  }) {
    _wheres.add({
      'type': 'any',
      'columns': columns,
      'operator': operator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds a WHERE clause where no column should match the given value.
  ///
  /// [columns] is the list of column names.
  /// [value] is the value to compare.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.whereNone(['title', 'lyrics', 'tags'], '%explicit%', operator: 'like')
  /// ```
  QueryBuilder whereNone(
    List<String> columns,
    Object? value, {
    String operator = '=',
  }) {
    _wheres.add({
      'type': 'none',
      'columns': columns,
      'operator': operator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds a WHERE IN condition to the query.
  ///
  /// [column] is the column name.
  /// [values] is the list of values to check against.
  ///
  /// Example:
  /// ```dart
  /// query.whereIn('id', [1, 2, 3])
  /// ```
  QueryBuilder whereIn(String column, List<Object?> values) {
    _wheres.add({
      'type': 'in',
      'column': column,
      'values': values,
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds a WHERE NOT IN condition to the query.
  ///
  /// [column] is the column name.
  /// [values] is the list of values to exclude.
  ///
  /// Example:
  /// ```dart
  /// query.whereNotIn('id', [1, 2, 3])
  /// ```
  QueryBuilder whereNotIn(String column, List<Object?> values) {
    _wheres.add({
      'type': 'in',
      'column': column,
      'values': values,
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds a WHERE NULL condition to the query.
  ///
  /// [column] is the column name to check for NULL.
  ///
  /// Example:
  /// ```dart
  /// query.whereNull('deleted_at')
  /// ```
  QueryBuilder whereNull(String column) {
    _wheres.add({
      'type': 'null',
      'column': column,
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds a WHERE NOT NULL condition to the query.
  ///
  /// [column] is the column name to check for NOT NULL.
  ///
  /// Example:
  /// ```dart
  /// query.whereNotNull('email')
  /// ```
  QueryBuilder whereNotNull(String column) {
    _wheres.add({
      'type': 'null',
      'column': column,
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds a WHERE BETWEEN condition to the query.
  ///
  /// [column] is the column name.
  /// [min] is the minimum value.
  /// [max] is the maximum value.
  ///
  /// Example:
  /// ```dart
  /// query.whereBetween('votes', min: 1, max: 100)
  /// ```
  QueryBuilder whereBetween(
    String column, {
    required Object? min,
    required Object? max,
  }) {
    _wheres.add({
      'type': 'between',
      'column': column,
      'values': [min, max],
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds a WHERE NOT BETWEEN condition to the query.
  ///
  /// [column] is the column name.
  /// [min] is the minimum value.
  /// [max] is the maximum value.
  ///
  /// Example:
  /// ```dart
  /// query.whereNotBetween('votes', min: 1, max: 100)
  /// ```
  QueryBuilder whereNotBetween(
    String column, {
    required Object? min,
    required Object? max,
  }) {
    _wheres.add({
      'type': 'between',
      'column': column,
      'values': [min, max],
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds a WHERE clause checking if a column's value is between two other columns.
  ///
  /// [column] is the column name to check.
  /// [minColumn] is the minimum column name.
  /// [maxColumn] is the maximum column name.
  ///
  /// Example:
  /// ```dart
  /// query.whereBetweenColumns('weight', minColumn: 'minimum_allowed_weight', maxColumn: 'maximum_allowed_weight')
  /// ```
  QueryBuilder whereBetweenColumns(
    String column, {
    required String minColumn,
    required String maxColumn,
  }) {
    _wheres.add({
      'type': 'betweenColumns',
      'column': column,
      'betweenColumns': [minColumn, maxColumn],
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds a WHERE clause checking if a column's value is NOT between two other columns.
  ///
  /// [column] is the column name to check.
  /// [minColumn] is the minimum column name.
  /// [maxColumn] is the maximum column name.
  ///
  /// Example:
  /// ```dart
  /// query.whereNotBetweenColumns('weight', minColumn: 'minimum_allowed_weight', maxColumn: 'maximum_allowed_weight')
  /// ```
  QueryBuilder whereNotBetweenColumns(
    String column, {
    required String minColumn,
    required String maxColumn,
  }) {
    _wheres.add({
      'type': 'betweenColumns',
      'column': column,
      'betweenColumns': [minColumn, maxColumn],
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds a GROUP BY clause to the query.
  ///
  /// [column] is the column name to group by.
  /// Can be called multiple times to group by multiple columns.
  ///
  /// Example:
  /// ```dart
  /// query.groupBy('account_id')
  /// query.groupBy('first_name').groupBy('status')
  /// ```
  QueryBuilder groupBy(String column) {
    _groups.add(column);
    return this;
  }

  /// Adds a HAVING clause to the query.
  ///
  /// [column] is the column name (usually an aggregate).
  /// [value] is the value to compare.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.groupBy('account_id').having('account_id', 100, operator: '>')
  /// ```
  QueryBuilder having(String column, Object? value, {String operator = '='}) {
    _havings.add({
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Makes the query return only distinct records.
  ///
  /// Example:
  /// ```dart
  /// query.distinct().get()
  /// ```
  QueryBuilder distinct() {
    _distinct = true;
    return this;
  }

  /// Returns the average value of a column.
  ///
  /// [column] is the column name to average.
  ///
  /// Example:
  /// ```dart
  /// final avgAge = await query.avg('age');
  /// ```
  Future<double> avg(String column) async {
    return _aggregate('AVG', column);
  }

  /// Returns the sum of a column's values.
  ///
  /// [column] is the column name to sum.
  ///
  /// Example:
  /// ```dart
  /// final totalVotes = await query.sum('votes');
  /// ```
  Future<double> sum(String column) async {
    return _aggregate('SUM', column);
  }

  /// Returns the maximum value of a column.
  ///
  /// [column] is the column name.
  ///
  /// Example:
  /// ```dart
  /// final maxPrice = await query.max('price');
  /// ```
  Future<double> max(String column) async {
    return _aggregate('MAX', column);
  }

  /// Returns the minimum value of a column.
  ///
  /// [column] is the column name.
  ///
  /// Example:
  /// ```dart
  /// final minPrice = await query.min('price');
  /// ```
  Future<double> min(String column) async {
    return _aggregate('MIN', column);
  }

  /// Helper method for aggregate functions.
  Future<double> _aggregate(String function, String column) async {
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: ['$function($column) as aggregate'],
      wheres: _wheres,
      joins: _joins,
      orders: [],
      groups: [],
      havings: [],
      distinct: false,
      limit: null,
      offset: null,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) {
      return 0.0;
    }

    final value = results.first['aggregate'];
    if (value == null) {
      return 0.0;
    }

    // Convert to double
    if (value is double) {
      return value;
    } else if (value is int) {
      return value.toDouble();
    } else if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }

    return 0.0;
  }

  /// Checks if any records exist for the current query.
  ///
  /// Returns `true` if at least one record exists, `false` otherwise.
  ///
  /// Example:
  /// ```dart
  /// final hasActiveUsers = await query.where('status', 'active').exists();
  /// ```
  Future<bool> exists() async {
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: ['1'],
      wheres: _wheres,
      joins: _joins,
      orders: [],
      groups: [],
      havings: [],
      distinct: false,
      limit: 1,
      offset: null,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);
    return results.isNotEmpty;
  }

  /// Checks if no records exist for the current query.
  ///
  /// Returns `true` if no records exist, `false` if at least one exists.
  ///
  /// Example:
  /// ```dart
  /// final noActiveUsers = await query.where('status', 'active').doesntExist();
  /// ```
  Future<bool> doesntExist() async {
    return !(await exists());
  }

  /// Retrieves a single column's values from the query results.
  ///
  /// If [key] is provided, returns a Map with [key] column as keys and [column] as values.
  /// If [key] is null, returns a List of [column] values.
  ///
  /// Example:
  /// ```dart
  /// // Get a list of names
  /// final names = await query.pluck('name') as List<Object?>;
  ///
  /// // Get a map of id => name
  /// final nameMap = await query.pluck('name', key: 'id') as Map<Object?, Object?>;
  /// ```
  Future<dynamic> pluck(String column, {String? key}) async {
    final columns = key != null ? [key, column] : [column];

    final compiled = _grammar.compileSelect(
      table: _table,
      columns: columns,
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      groups: _groups,
      havings: _havings,
      distinct: _distinct,
      limit: _limit,
      offset: _offset,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (key != null) {
      // Return as Map
      final map = <Object?, Object?>{};
      for (final row in results) {
        map[row[key]] = row[column];
      }
      return map;
    } else {
      // Return as List
      return results.map((row) => row[column]).toList();
    }
  }

  /// Retrieves a single column's value from the first result.
  ///
  /// Returns null if no records are found.
  ///
  /// Example:
  /// ```dart
  /// final email = await query.where('name', 'John').value('email');
  /// ```
  Future<Object?> value(String column) async {
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: [column],
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      groups: _groups,
      havings: _havings,
      distinct: _distinct,
      limit: 1,
      offset: _offset,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) {
      return null;
    }

    return results.first[column];
  }

  /// Increments a column's value by a given amount.
  ///
  /// [column] is the column name to increment.
  /// [amount] is the amount to increment by (defaults to 1).
  /// [extra] is an optional map of additional columns to update.
  ///
  /// Example:
  /// ```dart
  /// await query.where('id', 1).increment('votes');
  /// await query.where('id', 1).increment('votes', amount: 5);
  /// await query.where('id', 1).increment('votes', extra: {'updated_at': DateTime.now()});
  /// ```
  Future<void> increment(
    String column, {
    int amount = 1,
    Map<String, Object?>? extra,
  }) async {
    final bindings = <Object?>[];
    final buffer = StringBuffer('update $_table set $column = $column + ?');
    bindings.add(amount);

    if (extra != null && extra.isNotEmpty) {
      for (final entry in extra.entries) {
        buffer.write(', ${entry.key} = ?');
        bindings.add(entry.value);
      }
    }

    if (_wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(bindings));
    }

    await _laconic.statement(buffer.toString(), bindings);
  }

  /// Decrements a column's value by a given amount.
  ///
  /// [column] is the column name to decrement.
  /// [amount] is the amount to decrement by (defaults to 1).
  /// [extra] is an optional map of additional columns to update.
  ///
  /// Example:
  /// ```dart
  /// await query.where('id', 1).decrement('votes');
  /// await query.where('id', 1).decrement('votes', amount: 5);
  /// await query.where('id', 1).decrement('votes', extra: {'updated_at': DateTime.now()});
  /// ```
  Future<void> decrement(
    String column, {
    int amount = 1,
    Map<String, Object?>? extra,
  }) async {
    final bindings = <Object?>[];
    final buffer = StringBuffer('update $_table set $column = $column - ?');
    bindings.add(amount);

    if (extra != null && extra.isNotEmpty) {
      for (final entry in extra.entries) {
        buffer.write(', ${entry.key} = ?');
        bindings.add(entry.value);
      }
    }

    if (_wheres.isNotEmpty) {
      buffer.write(' where ');
      buffer.write(_compileWheres(bindings));
    }

    await _laconic.statement(buffer.toString(), bindings);
  }

  /// Helper method to compile WHERE conditions for increment/decrement.
  String _compileWheres(List<Object?> bindings) {
    final parts = <String>[];

    for (var i = 0; i < _wheres.length; i++) {
      final where = _wheres[i];
      final boolean = i == 0 ? '' : ' ${where['boolean']} ';
      final type = where['type'];

      if (type == 'basic') {
        parts.add('$boolean${where['column']} ${where['operator']} ?');
        bindings.add(where['value']);
      } else if (type == 'column') {
        parts.add(
          '$boolean${where['first']} ${where['operator']} ${where['second']}',
        );
      } else if (type == 'in') {
        final column = where['column'];
        final values = where['values'] as List<Object?>;
        final not = where['not'] as bool;
        final inKeyword = not ? 'not in' : 'in';

        if (values.isEmpty) {
          parts.add('$boolean${not ? '1 = 1' : '1 = 0'}');
        } else {
          final placeholders = List.filled(values.length, '?').join(', ');
          parts.add('$boolean$column $inKeyword ($placeholders)');
          bindings.addAll(values);
        }
      } else if (type == 'null') {
        final column = where['column'];
        final not = where['not'] as bool;
        final nullKeyword = not ? 'is not null' : 'is null';
        parts.add('$boolean$column $nullKeyword');
      } else if (type == 'between') {
        final column = where['column'];
        final values = where['values'] as List<Object?>;
        final not = where['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add('$boolean$column $betweenKeyword ? and ?');
        bindings.addAll(values);
      } else if (type == 'betweenColumns') {
        final column = where['column'];
        final betweenColumns = where['betweenColumns'] as List<String>;
        final not = where['not'] as bool;
        final betweenKeyword = not ? 'not between' : 'between';
        parts.add(
          '$boolean$column $betweenKeyword ${betweenColumns[0]} and ${betweenColumns[1]}',
        );
      } else if (type == 'all') {
        final columns = where['columns'] as List<String>;
        final operator = where['operator'];
        final value = where['value'];
        final conditions = columns
            .map((col) => '$col $operator ?')
            .join(' and ');
        parts.add('$boolean($conditions)');
        for (var j = 0; j < columns.length; j++) {
          bindings.add(value);
        }
      } else if (type == 'any') {
        final columns = where['columns'] as List<String>;
        final operator = where['operator'];
        final value = where['value'];
        final conditions = columns
            .map((col) => '$col $operator ?')
            .join(' or ');
        parts.add('$boolean($conditions)');
        for (var j = 0; j < columns.length; j++) {
          bindings.add(value);
        }
      } else if (type == 'none') {
        final columns = where['columns'] as List<String>;
        final operator = where['operator'];
        final value = where['value'];
        final conditions = columns
            .map((col) => '$col $operator ?')
            .join(' or ');
        parts.add('${boolean}not ($conditions)');
        for (var j = 0; j < columns.length; j++) {
          bindings.add(value);
        }
      }
    }

    return parts.join('');
  }
}
