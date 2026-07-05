import 'package:laconic/src/exception.dart';
import 'package:laconic/src/laconic.dart';
import 'package:laconic/src/grammar/grammar.dart';
import 'package:laconic/src/grammar/compiled_query.dart';
import 'package:laconic/src/query_builder/join_clause.dart';
import 'package:laconic/src/result.dart';

/// Fluent query builder for constructing and executing database queries.
class QueryBuilder {
  final Laconic _laconic;
  final SqlGrammar _grammar;

  /// The table name for the query.
  String _table;

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

  /// UNION clauses.
  final List<Map<String, dynamic>> _unions = [];

  /// The LIMIT value.
  int? _limit;

  /// The OFFSET value.
  int? _offset;

  /// Lock clauses (FOR UPDATE / FOR SHARE).
  final List<Map<String, dynamic>> _locks = [];

  /// Creates a new query builder instance.
  QueryBuilder({required Laconic laconic, required String table})
    : _laconic = laconic,
      _table = table,
      _grammar = laconic.grammar;

  /// Returns the count of records matching the query.
  ///
  /// Uses SQL COUNT(*) aggregate function for optimal performance.
  /// When GROUP BY is present, wraps the query in a subquery to count
  /// groups server-side instead of fetching all rows.
  Future<int> count() async {
    if (_hasEmptyWhereIn()) return 0;

    if (_groups.isNotEmpty) {
      // Wrap grouped query in a subquery to count groups server-side.
      // This avoids fetching all grouped rows over the network.
      final innerCompiled = _grammar.compileSelect(
        table: _table,
        columns: ['1'],
        wheres: _wheres,
        joins: _joins,
        orders: [],
        groups: _groups,
        havings: _havings,
        distinct: false,
        limit: null,
        offset: null,
      locks: _locks,
      );
      final sql = 'SELECT COUNT(*) as aggregate FROM (${innerCompiled.sql}) as laconic_sub';
      final results = await _laconic.select(sql, innerCompiled.bindings);

      if (results.isEmpty) return 0;
      final value = results.first['aggregate'];
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    final compiled = _grammar.compileSelect(
      table: _table,
      columns: ['COUNT(*) as aggregate'],
      wheres: _wheres,
      joins: _joins,
      orders: [],
      groups: _groups,
      havings: _havings,
      distinct: false,
      limit: null,
      offset: null,
      locks: _locks,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) return 0;

    final value = results.first['aggregate'];
    if (value == null) return 0;

    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;

    return 0;
  }

  /// Deletes records matching the query.
  ///
  /// By default, calling delete() without a WHERE clause will throw a
  /// [LaconicException] to prevent accidental deletion of all records.
  /// Set [allowWithoutWhere] to `true` to explicitly allow this.
  Future<void> delete({bool allowWithoutWhere = false}) async {
    if (_wheres.isEmpty && !allowWithoutWhere) {
      throw LaconicException(
        'Calling delete() without WHERE clause will delete all records. '
        'Use delete(allowWithoutWhere: true) if this is intentional.',
      );
    }

    final compiled = _grammar.compileDelete(table: _table, wheres: _wheres);

    await _laconic.statement(compiled.sql, compiled.bindings);
  }

  /// Truncates the table, removing all rows and resetting auto-increment.
  /// Unlike [delete], this does not require a WHERE clause.
  Future<void> truncate() async {
    final compiled = _grammar.compileTruncate(table: _table);
    await _laconic.statement(compiled.sql, compiled.bindings);
  }

  /// Returns the first record matching the query.
  ///
  /// Always appends `LIMIT 1` for efficiency, regardless of any
  /// previously set [limit] on the builder.
  ///
  /// Throws [LaconicException] if no record is found.
  Future<LaconicResult> first() async {
    if (_hasEmptyWhereIn()) throw LaconicException('No record found');
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: _columns,
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      groups: _groups,
      havings: _havings,
      distinct: _distinct,
      limit: 1,
      offset: _offset,
      locks: _locks,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) {
      throw LaconicException('No record found');
    }

    return results.first;
  }

  /// Returns all records matching the query.
  Future<List<LaconicResult>> get() async {
    if (_hasEmptyWhereIn()) return [];

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
      locks: _locks,
    );

    if (_unions.isEmpty) {
      return await _laconic.select(compiled.sql, compiled.bindings);
    }

    // Build UNIONs
    final sql = StringBuffer(compiled.sql);
    final allBindings = List<Object?>.from(compiled.bindings);
    for (final u in _unions) {
      sql.write(u['all'] == true ? ' union all ' : ' union ');
      sql.write(u['sql'] as String);
      allBindings.addAll(u['bindings'] as List<Object?>);
    }
    return await _laconic.select(sql.toString(), allBindings);
  }

  /// Returns the first record with the given [id]
  /// (shorthand for `where('id', id).first()`).
  Future<LaconicResult> find(Object? id) async {
    return where('id', id).first();
  }

  /// Returns the first record where [column] matches [value]
  /// (shorthand for `where(column, value).first()`).
  Future<LaconicResult> firstWhere(String column, Object? value) async {
    return where(column, value).first();
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

  /// Inserts records while ignoring duplicate key errors.
  /// For SQLite: `INSERT OR IGNORE INTO ...`. For MySQL: `INSERT IGNORE INTO ...`.
  Future<void> insertOrIgnore(List<Map<String, Object?>> data) async {
    if (data.isEmpty) throw LaconicException('Cannot insert an empty list of data');
    final compiled = _grammar.compileInsertOrIgnore(table: _table, data: data);
    await _laconic.statement(compiled.sql, compiled.bindings);
  }

  /// Performs an upsert: inserts new records or updates existing ones.
  ///
  /// [uniqueBy] lists the columns that determine uniqueness.
  /// If [update] is null, all non-unique columns are updated on conflict.
  Future<void> upsert(
    List<Map<String, Object?>> data, {
    required List<String> uniqueBy,
    List<String>? update,
  }) async {
    if (data.isEmpty) throw LaconicException('Cannot upsert an empty list of data');
    final compiled = _grammar.compileUpsert(
      table: _table,
      data: data,
      uniqueBy: uniqueBy,
      update: update,
    );
    await _laconic.statement(compiled.sql, compiled.bindings);
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
    final joinClause = JoinClause(_laconic);
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
    final joinClause = JoinClause(_laconic);
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
    final joinClause = JoinClause(_laconic);
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

  /// Sets the table for this query (useful for subqueries and EXISTS clauses).
  QueryBuilder from(String table) {
    _table = table;
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

  /// Adds a `FOR UPDATE` lock to the query.
  QueryBuilder lockForUpdate() {
    _locks.add({'type': 'for_update'});
    return this;
  }

  /// Adds a `FOR SHARE` (PG) / `LOCK IN SHARE MODE` (MySQL) lock.
  QueryBuilder sharedLock() {
    _locks.add({'type': 'for_share'});
    return this;
  }

  /// Adds a UNION clause. [all] = true for UNION ALL.
  QueryBuilder union(void Function(QueryBuilder) callback, {bool all = false}) {
    final uq = QueryBuilder(laconic: _laconic, table: '');
    callback(uq);
    final compiled = uq.compileAsSubquery();
    _unions.add({'sql': compiled.sql, 'bindings': compiled.bindings, 'all': all});
    return this;
  }

  /// Adds a UNION ALL clause.
  QueryBuilder unionAll(void Function(QueryBuilder) callback) {
    return union(callback, all: true);
  }

  /// Adds an ORDER BY clause to the query.
  ///
  /// [column] is the column name to order by.
  /// [direction] must be 'asc' or 'desc' (defaults to 'asc').
  QueryBuilder orderBy(String column, {String direction = 'asc'}) {
    _orders.add({'column': column, 'direction': direction});
    return this;
  }

  /// Adds a raw ORDER BY expression.
  ///
  /// Example:
  /// ```dart
  /// query.orderByRaw('RANDOM()');
  /// query.orderByRaw('FIELD(status, ?, ?, ?)', ['active', 'pending', 'inactive']);
  /// ```
  QueryBuilder orderByRaw(String sql, [List<Object?> bindings = const []]) {
    _orders.add({'type': 'raw', 'sql': sql, 'bindings': bindings});
    return this;
  }

  /// Adds an ORDER BY ... DESC clause (shorthand).
  QueryBuilder orderByDesc(String column) {
    return orderBy(column, direction: 'desc');
  }

  /// Orders by `created_at` descending (most recent first).
  QueryBuilder latest({String column = 'created_at'}) {
    return orderBy(column, direction: 'desc');
  }

  /// Orders by `created_at` ascending (oldest first).
  QueryBuilder oldest({String column = 'created_at'}) {
    return orderBy(column, direction: 'asc');
  }

  /// Orders results in random order.
  QueryBuilder inRandomOrder() {
    return orderByRaw('RANDOM()');
  }

  /// Removes all previously set ORDER BY clauses.
  QueryBuilder reorder() {
    _orders.clear();
    return this;
  }

  /// Alias for [offset]. Skips the specified number of records.
  QueryBuilder skip(int count) {
    return offset(count);
  }

  /// Alias for [limit]. Takes the specified number of records.
  QueryBuilder take(int count) {
    return limit(count);
  }

  /// Sets LIMIT and OFFSET for a given page number (1-indexed).
  QueryBuilder forPage(int page, {int perPage = 15}) {
    return limit(perPage).offset((page - 1) * perPage);
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
      'comparator': comparator,
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds an OR WHERE NOT EQUAL condition.
  QueryBuilder orWhereNot(String column, Object? value) {
    return orWhere(column, value, comparator: '!=');
  }

  /// Adds an OR WHERE LIKE condition.
  QueryBuilder orWhereLike(String column, Object? value) {
    return orWhere(column, value, comparator: 'like');
  }

  /// Adds an OR WHERE NOT LIKE condition.
  QueryBuilder orWhereNotLike(String column, Object? value) {
    return orWhere(column, value, comparator: 'not like');
  }

  /// Adds a raw WHERE condition.
  ///
  /// The [sql] is inserted directly into the WHERE clause. Use [bindings]
  /// for parameterized values.
  ///
  /// Example:
  /// ```dart
  /// query.whereRaw('created_at > NOW()');
  /// query.whereRaw('price > ? AND status = ?', [100, 'active']);
  /// ```
  QueryBuilder whereRaw(String sql, [List<Object?> bindings = const []]) {
    _wheres.add({
      'type': 'raw',
      'sql': sql,
      'bindings': bindings,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR raw WHERE condition.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereRaw('deleted_at IS NULL');
  /// ```
  QueryBuilder orWhereRaw(String sql, [List<Object?> bindings = const []]) {
    _wheres.add({
      'type': 'raw',
      'sql': sql,
      'bindings': bindings,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a nested WHERE group (parenthesized sub-conditions).
  ///
  /// The [callback] receives a fresh [QueryBuilder] for building the
  /// sub-group's conditions. Conditions are joined with AND.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active')
  ///      .whereNested((q) => q.where('age', 30).orWhere('role', 'admin'));
  /// // SQL: WHERE status = ? AND (age = ? OR role = ?)
  /// ```
  QueryBuilder whereNested(void Function(QueryBuilder) callback) {
    return _nestedWhere(callback, 'and');
  }

  /// Adds an OR nested WHERE group.
  QueryBuilder orWhereNested(void Function(QueryBuilder) callback) {
    return _nestedWhere(callback, 'or');
  }

  QueryBuilder _nestedWhere(
    void Function(QueryBuilder) callback,
    String boolean,
  ) {
    final nested = QueryBuilder(laconic: _laconic, table: _table);
    callback(nested);
    _wheres.add({
      'type': 'nested',
      'conditions': nested._wheres,
      'boolean': boolean,
    });
    return this;
  }

  /// Adds a WHERE EXISTS clause with a subquery.
  ///
  /// The [callback] receives a fresh [QueryBuilder] for building the
  /// subquery. Use [from] to set the table.
  ///
  /// Example:
  /// ```dart
  /// query.whereExists((q) =>
  ///   q.from('orders').whereColumn('orders.user_id', 'users.id'));
  /// ```
  QueryBuilder whereExists(void Function(QueryBuilder) callback) {
    return _addExists(callback, 'and', false);
  }

  /// Adds an OR WHERE EXISTS clause.
  QueryBuilder orWhereExists(void Function(QueryBuilder) callback) {
    return _addExists(callback, 'or', false);
  }

  /// Adds a WHERE NOT EXISTS clause.
  QueryBuilder whereNotExists(void Function(QueryBuilder) callback) {
    return _addExists(callback, 'and', true);
  }

  /// Adds an OR WHERE NOT EXISTS clause.
  QueryBuilder orWhereNotExists(void Function(QueryBuilder) callback) {
    return _addExists(callback, 'or', true);
  }

  QueryBuilder _addExists(
    void Function(QueryBuilder) callback,
    String boolean,
    bool not,
  ) {
    final subQuery = QueryBuilder(laconic: _laconic, table: '');
    callback(subQuery);
    final compiled = subQuery.compileAsSubquery();
    _wheres.add({
      'type': 'exists',
      'sql': compiled.sql,
      'bindings': compiled.bindings,
      'boolean': boolean,
      'not': not,
    });
    return this;
  }

  /// Compiles this builder's current state as a SELECT subquery.
  /// @internal Used by [JoinClause] for EXISTS subqueries.
  CompiledQuery compileAsSubquery() {
    return _grammar.compileSelect(
      table: _table,
      columns: ['1'],
      wheres: _wheres,
      joins: _joins,
      orders: [],
      groups: [],
      havings: [],
      distinct: false,
      limit: null,
      offset: null,
      locks: _locks,
    );
  }

  /// Processes query results in chunks to avoid memory issues.
  Future<void> chunk(int count, Future<void> Function(List<LaconicResult>) callback) async {
    var page = 1;
    while (true) {
      final results = await clone().forPage(page, perPage: count).get();
      if (results.isEmpty) break;
      await callback(results);
      if (results.length < count) break;
      page++;
    }
  }

  /// Processes results in chunks using ID-based pagination (avoids large OFFSET).
  Future<void> chunkById(int count, Future<void> Function(List<LaconicResult>) callback,
      {String column = 'id', String? alias}) async {
    final col = alias != null ? '$alias.$column' : column;
    Object? lastId;
    while (true) {
      final q = clone();
      if (lastId != null) q.where(col, lastId, comparator: '>');
      final results = await q.orderBy(col).limit(count).get();
      if (results.isEmpty) break;
      await callback(results);
      if (results.length < count) break;
      lastId = results.last[column];
    }
  }

  /// Iterates over each result using chunking.
  Future<void> each(Future<void> Function(LaconicResult) callback, {int count = 1000}) async {
    await chunk(count, (results) async {
      for (final row in results) {
        await callback(row);
      }
    });
  }

  /// Returns a deep copy of this QueryBuilder for reuse.
  QueryBuilder clone() {
    final copy = QueryBuilder(laconic: _laconic, table: _table)
      .._columns = List<String>.from(_columns)
      .._wheres.addAll(_wheres.map((w) => Map<String, dynamic>.from(w)))
      .._joins.addAll(_joins.map((j) => Map<String, dynamic>.from(j)))
      .._orders.addAll(_orders.map((o) => Map<String, dynamic>.from(o)))
      .._groups.addAll(_groups)
      .._havings.addAll(_havings.map((h) => Map<String, dynamic>.from(h)))
      .._distinct = _distinct
      .._limit = _limit
      .._offset = _offset
      .._locks.addAll(_locks.map((l) => Map<String, dynamic>.from(l)))
      .._unions.addAll(_unions.map((u) => Map<String, dynamic>.from(u)));
    return copy;
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

  /// Adds a raw SELECT expression.
  ///
  /// The [sql] is inserted directly into the SELECT clause without
  /// parameterization or column-name wrapping.
  ///
  /// Example:
  /// ```dart
  /// query.selectRaw('COUNT(*) as count');
  /// query.select(['name']).selectRaw('COUNT(*) as count');
  /// ```
  QueryBuilder selectRaw(String sql) {
    if (_columns.length == 1 && _columns[0] == '*') {
      _columns = [sql];
    } else {
      _columns.add(sql);
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

  /// Executes a callback when the given condition is false.
  ///
  /// The inverse of [when]. [callback] is executed if [condition] is false.
  /// [otherwise] is optionally executed if [condition] is true.
  QueryBuilder unless(
    bool condition,
    void Function(QueryBuilder) callback, {
    void Function(QueryBuilder)? otherwise,
  }) {
    return when(!condition, callback, otherwise: otherwise);
  }

  /// Returns a single record matching the query.
  ///
  /// Throws [LaconicException] if no record is found or if multiple records are found.
  /// Use this method when you expect exactly one result.
  ///
  /// Example:
  /// ```dart
  /// // Throws if user doesn't exist or if multiple users match
  /// final user = await query.where('email', 'john@example.com').sole();
  /// ```
  Future<LaconicResult> sole() async {
    if (_hasEmptyWhereIn()) throw LaconicException('No record found');
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: _columns,
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      groups: _groups,
      havings: _havings,
      distinct: _distinct,
      limit: 2,
      offset: _offset,
      locks: _locks,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) {
      throw LaconicException('No record found');
    }

    if (results.length > 1) {
      throw LaconicException(
        'Multiple records found when exactly one was expected',
      );
    }

    return results.first;
  }

  /// Updates records matching the query.
  ///
  /// [data] is a map of column-value pairs to update. Must be non-empty.
  Future<void> update(Map<String, Object?> data) async {
    if (data.isEmpty) {
      throw LaconicException('Cannot update with an empty data map');
    }
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
      'comparator': comparator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds a WHERE NOT EQUAL condition (shorthand).
  QueryBuilder whereNot(String column, Object? value) {
    return where(column, value, comparator: '!=');
  }

  /// Adds a WHERE LIKE condition (shorthand).
  QueryBuilder whereLike(String column, Object? value) {
    return where(column, value, comparator: 'like');
  }

  /// Adds a WHERE NOT LIKE condition (shorthand).
  QueryBuilder whereNotLike(String column, Object? value) {
    return where(column, value, comparator: 'not like');
  }

  /// Adds a WHERE clause comparing two columns.
  ///
  /// [first] is the first column name.
  /// [second] is the second column name.
  /// [comparator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.whereColumn('first_name', 'last_name')
  /// query.whereColumn('updated_at', 'created_at', comparator: '>')
  /// ```
  QueryBuilder whereColumn(
    String first,
    String second, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'column',
      'first': first,
      'comparator': comparator,
      'second': second,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds a WHERE clause where all columns must match the given value.
  ///
  /// [columns] is the list of column names.
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.whereAll(['title', 'content'], '%Laravel%', comparator: 'like')
  /// ```
  QueryBuilder whereAll(
    List<String> columns,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'all',
      'columns': columns,
      'comparator': comparator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds a WHERE clause where any column can match the given value.
  ///
  /// [columns] is the list of column names.
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.whereAny(['name', 'email', 'phone'], 'Example%', comparator: 'like')
  /// ```
  QueryBuilder whereAny(
    List<String> columns,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'any',
      'columns': columns,
      'comparator': comparator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds a WHERE clause where no column should match the given value.
  ///
  /// [columns] is the list of column names.
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.whereNone(['title', 'lyrics', 'tags'], '%explicit%', comparator: 'like')
  /// ```
  QueryBuilder whereNone(
    List<String> columns,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'none',
      'columns': columns,
      'comparator': comparator,
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

  /// Adds an OR WHERE clause comparing two columns.
  ///
  /// [first] is the first column name.
  /// [second] is the second column name.
  /// [comparator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereColumn('updated_at', 'created_at', comparator: '>')
  /// ```
  QueryBuilder orWhereColumn(
    String first,
    String second, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'column',
      'first': first,
      'comparator': comparator,
      'second': second,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds an OR WHERE IN condition to the query.
  ///
  /// [column] is the column name.
  /// [values] is the list of values to check against.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereIn('id', [1, 2, 3])
  /// ```
  QueryBuilder orWhereIn(String column, List<Object?> values) {
    _wheres.add({
      'type': 'in',
      'column': column,
      'values': values,
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds an OR WHERE NOT IN condition to the query.
  ///
  /// [column] is the column name.
  /// [values] is the list of values to exclude.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereNotIn('id', [1, 2, 3])
  /// ```
  QueryBuilder orWhereNotIn(String column, List<Object?> values) {
    _wheres.add({
      'type': 'in',
      'column': column,
      'values': values,
      'boolean': 'or',
      'not': true,
    });
    return this;
  }

  /// Adds an OR WHERE NULL condition to the query.
  ///
  /// [column] is the column name to check for NULL.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereNull('deleted_at')
  /// ```
  QueryBuilder orWhereNull(String column) {
    _wheres.add({
      'type': 'null',
      'column': column,
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds an OR WHERE NOT NULL condition to the query.
  ///
  /// [column] is the column name to check for NOT NULL.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereNotNull('email')
  /// ```
  QueryBuilder orWhereNotNull(String column) {
    _wheres.add({
      'type': 'null',
      'column': column,
      'boolean': 'or',
      'not': true,
    });
    return this;
  }

  /// WHERE DATE(col) = value.
  QueryBuilder whereDate(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'date', 'column': column, 'value': value, 'boolean': 'and'});
    return this;
  }
  /// OR WHERE DATE(col) = value.
  QueryBuilder orWhereDate(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'date', 'column': column, 'value': value, 'boolean': 'or'});
    return this;
  }
  /// WHERE TIME(col) = value.
  QueryBuilder whereTime(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'time', 'column': column, 'value': value, 'boolean': 'and'});
    return this;
  }
  /// OR WHERE TIME(col) = value.
  QueryBuilder orWhereTime(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'time', 'column': column, 'value': value, 'boolean': 'or'});
    return this;
  }
  /// WHERE DAY(col) = value.
  QueryBuilder whereDay(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'day', 'column': column, 'value': value, 'boolean': 'and'});
    return this;
  }
  /// OR WHERE DAY(col) = value.
  QueryBuilder orWhereDay(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'day', 'column': column, 'value': value, 'boolean': 'or'});
    return this;
  }
  /// WHERE MONTH(col) = value.
  QueryBuilder whereMonth(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'month', 'column': column, 'value': value, 'boolean': 'and'});
    return this;
  }
  /// OR WHERE MONTH(col) = value.
  QueryBuilder orWhereMonth(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'month', 'column': column, 'value': value, 'boolean': 'or'});
    return this;
  }
  /// WHERE YEAR(col) = value.
  QueryBuilder whereYear(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'year', 'column': column, 'value': value, 'boolean': 'and'});
    return this;
  }
  /// OR WHERE YEAR(col) = value.
  QueryBuilder orWhereYear(String column, Object? value) {
    _wheres.add({'type': 'date', 'dateType': 'year', 'column': column, 'value': value, 'boolean': 'or'});
    return this;
  }

  /// Adds an OR WHERE BETWEEN condition to the query.
  ///
  /// [column] is the column name.
  /// [min] is the minimum value.
  /// [max] is the maximum value.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereBetween('votes', min: 1, max: 100)
  /// ```
  QueryBuilder orWhereBetween(
    String column, {
    required Object? min,
    required Object? max,
  }) {
    _wheres.add({
      'type': 'between',
      'column': column,
      'values': [min, max],
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds an OR WHERE NOT BETWEEN condition to the query.
  ///
  /// [column] is the column name.
  /// [min] is the minimum value.
  /// [max] is the maximum value.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereNotBetween('votes', min: 1, max: 100)
  /// ```
  QueryBuilder orWhereNotBetween(
    String column, {
    required Object? min,
    required Object? max,
  }) {
    _wheres.add({
      'type': 'between',
      'column': column,
      'values': [min, max],
      'boolean': 'or',
      'not': true,
    });
    return this;
  }

  /// Adds an OR WHERE clause checking if a column's value is between two other columns.
  ///
  /// [column] is the column name to check.
  /// [minColumn] is the minimum column name.
  /// [maxColumn] is the maximum column name.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereBetweenColumns('weight', minColumn: 'min_weight', maxColumn: 'max_weight')
  /// ```
  QueryBuilder orWhereBetweenColumns(
    String column, {
    required String minColumn,
    required String maxColumn,
  }) {
    _wheres.add({
      'type': 'betweenColumns',
      'column': column,
      'betweenColumns': [minColumn, maxColumn],
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds an OR WHERE clause checking if a column's value is NOT between two other columns.
  ///
  /// [column] is the column name to check.
  /// [minColumn] is the minimum column name.
  /// [maxColumn] is the maximum column name.
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereNotBetweenColumns('weight', minColumn: 'min_weight', maxColumn: 'max_weight')
  /// ```
  QueryBuilder orWhereNotBetweenColumns(
    String column, {
    required String minColumn,
    required String maxColumn,
  }) {
    _wheres.add({
      'type': 'betweenColumns',
      'column': column,
      'betweenColumns': [minColumn, maxColumn],
      'boolean': 'or',
      'not': true,
    });
    return this;
  }

  /// Adds an OR WHERE clause where all columns must match the given value.
  ///
  /// [columns] is the list of column names.
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereAll(['title', 'content'], '%Laravel%', comparator: 'like')
  /// ```
  QueryBuilder orWhereAll(
    List<String> columns,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'all',
      'columns': columns,
      'comparator': comparator,
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds an OR WHERE clause where any column can match the given value.
  ///
  /// [columns] is the list of column names.
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.where('status', 'active').orWhereAny(['name', 'email'], 'Example%', comparator: 'like')
  /// ```
  QueryBuilder orWhereAny(
    List<String> columns,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'any',
      'columns': columns,
      'comparator': comparator,
      'value': value,
      'boolean': 'or',
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

  /// Adds a raw GROUP BY expression.
  ///
  /// Example:
  /// ```dart
  /// query.groupByRaw('YEAR(created_at)');
  /// ```
  QueryBuilder groupByRaw(String sql) {
    _groups.add(sql);
    return this;
  }

  /// Adds a HAVING clause to the query.
  ///
  /// [column] is the column name (usually an aggregate).
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.groupBy('account_id').having('account_id', 100, comparator: '>')
  /// ```
  QueryBuilder having(String column, Object? value, {String comparator = '='}) {
    _havings.add({
      'column': column,
      'comparator': comparator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR HAVING clause to the query.
  ///
  /// [column] is the column name (usually an aggregate).
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.groupBy('account_id').having('account_id', 100, comparator: '>').orHaving('account_id', 50, comparator: '<')
  /// ```
  QueryBuilder orHaving(String column, Object? value, {String comparator = '='}) {
    _havings.add({
      'column': column,
      'comparator': comparator,
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a raw HAVING condition.
  ///
  /// Example:
  /// ```dart
  /// query.groupBy('account_id').havingRaw('SUM(amount) > ?', [1000]);
  /// ```
  QueryBuilder havingRaw(String sql, [List<Object?> bindings = const []]) {
    _havings.add({
      'type': 'raw',
      'sql': sql,
      'bindings': bindings,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR raw HAVING condition.
  QueryBuilder orHavingRaw(String sql, [List<Object?> bindings = const []]) {
    _havings.add({
      'type': 'raw',
      'sql': sql,
      'bindings': bindings,
      'boolean': 'or',
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
  Future<double?> avg(String column) async {
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
  Future<double?> sum(String column) async {
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
  Future<double?> max(String column) async {
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
  Future<double?> min(String column) async {
    return _aggregate('MIN', column);
  }

  /// Helper method for aggregate functions.
  ///
  /// Preserves all query clauses. When GROUP BY is present, returns the
  /// aggregate value from the first group only. For grouped aggregates
  /// that require all group values, use [get] with [selectRaw] instead.
  Future<double?> _aggregate(String function, String column) async {
    if (_hasEmptyWhereIn()) return null;

    final compiled = _grammar.compileSelect(
      table: _table,
      columns: ['$function($column) as aggregate'],
      wheres: _wheres,
      joins: _joins,
      orders: [],
      groups: _groups,
      havings: _havings,
      distinct: _distinct,
      limit: null,
      offset: null,
      locks: _locks,
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) {
      return null;
    }

    final value = results.first['aggregate'];
    if (value == null) {
      return null;
    }

    // Convert to double
    if (value is double) {
      return value;
    } else if (value is int) {
      return value.toDouble();
    } else if (value is String) {
      return double.tryParse(value);
    }

    return null;
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
    if (_hasEmptyWhereIn()) return false;
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
      locks: _locks,
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
    if (_hasEmptyWhereIn()) {
      return key != null ? <Object?, Object?>{} : <Object?>[];
    }
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
      locks: _locks,
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
    if (_hasEmptyWhereIn()) return null;
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
      locks: _locks,
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
    bool allowWithoutWhere = false,
  }) async {
    if (_wheres.isEmpty && !allowWithoutWhere) {
      throw LaconicException(
        'Calling increment() without WHERE clause will update all records. '
        'Use increment(..., allowWithoutWhere: true) if this is intentional.',
      );
    }

    final compiled = _grammar.compileIncrement(
      table: _table,
      column: column,
      amount: amount,
      extra: extra,
      wheres: _wheres,
    );

    await _laconic.statement(compiled.sql, compiled.bindings);
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
    bool allowWithoutWhere = false,
  }) async {
    if (_wheres.isEmpty && !allowWithoutWhere) {
      throw LaconicException(
        'Calling decrement() without WHERE clause will update all records. '
        'Use decrement(..., allowWithoutWhere: true) if this is intentional.',
      );
    }

    final compiled = _grammar.compileDecrement(
      table: _table,
      column: column,
      amount: amount,
      extra: extra,
      wheres: _wheres,
    );

    await _laconic.statement(compiled.sql, compiled.bindings);
  }

  /// Returns the compiled SQL for the current query without executing it.
  String toSql() {
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
      locks: _locks,
    );
    return compiled.sql;
  }

  /// Returns the parameter bindings for the current query without executing it.
  List<Object?> getBindings() {
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
      locks: _locks,
    );
    return compiled.bindings;
  }

  /// Dumps the compiled SQL and bindings to the console and returns [this]
  /// for continued chaining.
  QueryBuilder dump() {
    // ignore: avoid_print
    print('SQL: ${toSql()}');
    // ignore: avoid_print
    print('Bindings: ${getBindings()}');
    return this;
  }

  /// Dumps the compiled SQL and bindings to the console and throws
  /// a [LaconicException] to halt execution.
  Never dd() {
    dump();
    throw LaconicException('QueryBuilder.dd() called — execution halted');
  }

  /// Returns true if the query has an impossible WHERE condition that
  /// guarantees zero results — specifically, an AND-condition [whereIn]
  /// (not [whereNotIn]) with an empty values list.
  ///
  /// This allows the query builder to short-circuit and skip the database
  /// round-trip entirely.
  bool _hasEmptyWhereIn() {
    return _checkEmptyWhereIn(_wheres);
  }

  bool _checkEmptyWhereIn(List<Map<String, dynamic>> conditions) {
    for (final c in conditions) {
      if (c['type'] == 'in' &&
          c['boolean'] == 'and' &&
          !(c['not'] as bool) &&
          (c['values'] as List).isEmpty) {
        return true;
      }
      if (c['type'] == 'nested') {
        if (_checkEmptyWhereIn(
            c['conditions'] as List<Map<String, dynamic>>)) {
          return true;
        }
      }
    }
    return false;
  }
}
