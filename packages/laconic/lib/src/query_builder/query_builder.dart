import 'dart:typed_data';

import 'package:laconic/src/exception.dart';
import 'package:laconic/src/expression.dart';
import 'package:laconic/src/laconic.dart';
import 'package:laconic/src/operator.dart';
import 'package:laconic/src/pagination.dart';
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

  /// A compiled subquery used as the FROM source.
  CompiledQuery? _fromSubquery;

  /// Alias for [_fromSubquery]; `null` means raw FROM SQL.
  String? _fromAlias;

  /// The columns to select.
  List<String> _columns = ['*'];

  /// Bindings for raw SELECT expressions, in column order.
  final List<Object?> _selectBindings = [];

  /// Bindings for raw GROUP BY expressions, in group order.
  final List<Object?> _groupBindings = [];

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

  /// Whether PostgreSQL should compile `DISTINCT ON`.
  bool _distinctOn = false;

  /// UNION clauses.
  final List<Map<String, dynamic>> _unions = [];

  /// The LIMIT value.
  int? _limit;

  /// Per-partition row limit (`groupLimit`).
  Map<String, dynamic>? _groupLimit;

  /// The OFFSET value.
  int? _offset;

  /// Lock clauses (FOR UPDATE / FOR SHARE).
  final List<Map<String, dynamic>> _locks = [];

  /// MySQL index hints.
  final List<Map<String, String>> _indexHints = [];

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
  Future<int> count([String column = '*']) async {
    final isStar = column == '*';

    if (!isStar && (_groups.isNotEmpty || _unions.isNotEmpty)) {
      throw LaconicException(
        'count(column) is not supported with GROUP BY or UNION; use count()',
      );
    }

    if (_groups.isNotEmpty || _unions.isNotEmpty || (_distinct && isStar)) {
      final query = clone()..reorder();
      query._limit = null;
      query._offset = null;
      query._locks.clear();
      if (_unions.isEmpty &&
          _groups.isNotEmpty &&
          _columns.length == 1 &&
          _columns.first == '*') {
        query._columns = List.of(_groups);
      }
      final inner = query._compileSelect();
      final results = await _laconic.select(
        'select count($column) as aggregate from (${inner.sql}) as laconic_count',
        inner.bindings,
      );
      final value = results.isEmpty ? null : results.first['aggregate'];
      if (value == null) return 0;
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    final aggregate =
        _distinct
            ? 'COUNT(DISTINCT $column) as aggregate'
            : 'COUNT($column) as aggregate';
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: [aggregate],
      wheres: _wheres,
      joins: _joins,
      orders: [],
      groups: _groups,
      groupBindings: _groupBindings,
      havings: _havings,
      distinct: false,
      fromSubquery: _fromSubquery,
      fromAlias: _fromAlias,
      indexHints: _indexHints,
      limit: null,
      offset: null,
      locks: const [],
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) return 0;

    final value = results.first['aggregate'];
    if (value == null) return 0;

    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;

    return 0;
  }

  /// Deletes records matching the query.
  ///
  /// By default, calling delete() without a WHERE clause will throw a
  /// [LaconicException] to prevent accidental deletion of all records.
  /// Set [allowWithoutWhere] to `true` to explicitly allow this.
  ///
  /// Returns the number of affected rows reported by the database.
  Future<int> delete({bool allowWithoutWhere = false}) async {
    if (_wheres.isEmpty && !allowWithoutWhere) {
      throw LaconicException(
        'Calling delete() without WHERE clause will delete all records. '
        'Use delete(allowWithoutWhere: true) if this is intentional.',
      );
    }

    final compiled = _grammar.compileDelete(table: _table, wheres: _wheres);

    return _laconic.affectingStatement(compiled.sql, compiled.bindings);
  }

  /// Truncates the table, removing all rows and resetting auto-increment.
  /// Unlike [delete], this does not require a WHERE clause.
  Future<void> truncate() async {
    for (final compiled in _grammar.compileTruncateAll(table: _table)) {
      await _laconic.statement(compiled.sql, compiled.bindings);
    }
  }

  /// Returns the first record matching the query, or `null` when none exists.
  ///
  /// Always appends `LIMIT 1` for efficiency, regardless of any
  /// previously set [limit] on the builder.
  ///
  /// The `OrNull` suffix follows the Dart convention used by
  /// `Iterable.firstOrNull`; use [first] for fail-fast behavior.
  Future<LaconicResult?> firstOrNull() async {
    final compiled = _compileSelect(limitOverride: 1);

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    return results.isEmpty ? null : results.first;
  }

  /// Returns the first record matching the query.
  ///
  /// Always appends `LIMIT 1` for efficiency, regardless of any
  /// previously set [limit] on the builder.
  ///
  /// Throws [LaconicException] if no record is found. Equivalent to
  /// Laravel's `firstOrFail()`; use [firstOrNull] to receive `null` instead.
  Future<LaconicResult> first() async {
    final result = await firstOrNull();
    if (result == null) {
      throw LaconicException('No record found');
    }
    return result;
  }

  /// Returns the first record, or the result of [fallback] when none exists.
  Future<LaconicResult> firstOr(LaconicResult Function() fallback) async {
    return await firstOrNull() ?? fallback();
  }

  /// Alias for [first], matching Laravel's fail-fast name.
  Future<LaconicResult> firstOrFail() => first();

  /// Returns all records matching the query.
  Future<List<LaconicResult>> get() async {
    final compiled = _compileSelect();

    return _laconic.select(compiled.sql, compiled.bindings);
  }

  /// Returns the first record with the given [id], or `null` when none exists.
  Future<LaconicResult?> findOrNull(Object? id) {
    return where('id', id).firstOrNull();
  }

  /// Returns the first record with the given [id]
  /// (shorthand for `where('id', id).first()`).
  ///
  /// Throws [LaconicException] if no record is found.
  Future<LaconicResult> find(Object? id) async {
    final result = await findOrNull(id);
    if (result == null) {
      throw LaconicException('No record found');
    }
    return result;
  }

  /// Returns the record with [id], or the result of [fallback] when none
  /// exists.
  Future<LaconicResult> findOr(
    Object? id,
    LaconicResult Function() fallback,
  ) async {
    return await findOrNull(id) ?? fallback();
  }

  /// Alias for [find], matching Laravel's fail-fast name.
  Future<LaconicResult> findOrFail(Object? id) => find(id);

  /// Returns the first record where [column] matches [value], or `null`.
  Future<LaconicResult?> firstWhereOrNull(String column, Object? value) {
    return where(column, value).firstOrNull();
  }

  /// Returns the first record where [column] matches [value]
  /// (shorthand for `where(column, value).first()`).
  ///
  /// Throws [LaconicException] if no record is found.
  Future<LaconicResult> firstWhere(String column, Object? value) async {
    final result = await firstWhereOrNull(column, value);
    if (result == null) {
      throw LaconicException('No record found');
    }
    return result;
  }

  /// Inserts records into the database.
  ///
  /// [data] must be a non-empty list of maps where each map represents a row.
  /// All maps must have the same keys.
  Future<bool> insert(List<Map<String, Object?>> data) async {
    if (data.isEmpty) {
      throw LaconicException('Cannot insert an empty list of data');
    }

    final compiled = _grammar.compileInsert(table: _table, data: data);

    await _laconic.statement(compiled.sql, compiled.bindings);
    return true;
  }

  /// Inserts rows produced by a subquery:
  /// `insert into table (columns) <subquery>`.
  Future<bool> insertUsing(List<String> columns, Object query) async {
    if (columns.isEmpty) {
      throw LaconicException('insertUsing requires at least one column');
    }
    final compiled = _compileSubquery(query);
    final sql = 'insert into $_table (${columns.join(', ')}) ${compiled.sql}';
    await _laconic.statement(sql, compiled.bindings);
    return true;
  }

  /// Inserts rows produced by a subquery, ignoring duplicate-key errors.
  Future<bool> insertOrIgnoreUsing(List<String> columns, Object query) async {
    if (columns.isEmpty) {
      throw LaconicException(
        'insertOrIgnoreUsing requires at least one column',
      );
    }
    final compiled = _compileSubquery(query);
    final sql = _grammar.compileInsertOrIgnoreUsing(
      table: _table,
      columns: columns,
      sql: compiled.sql,
    );
    await _laconic.statement(sql, compiled.bindings);
    return true;
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
    if (data.isEmpty) {
      throw LaconicException('Cannot insert an empty list of data');
    }
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
    if (data.isEmpty) {
      throw LaconicException('Cannot upsert an empty list of data');
    }
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
  /// Note: SQLite versions before 3.39 do not support RIGHT JOIN. Modern
  /// SQLite (3.39+) supports it natively.
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

  /// Adds a MySQL `STRAIGHT_JOIN`. Other dialects compile a regular JOIN.
  QueryBuilder straightJoin(
    String targetTable,
    void Function(JoinClause) builder,
  ) {
    final joinClause = JoinClause(_laconic);
    builder(joinClause);
    _joins.add({
      'type': 'straight',
      'table': targetTable,
      'conditions': joinClause.conditions,
    });
    return this;
  }

  /// Adds an INNER JOIN whose ON condition compares a column with a value.
  QueryBuilder joinWhere(
    String targetTable,
    String first,
    String comparator,
    Object? second,
  ) {
    return _joinWithValue('inner', targetTable, first, comparator, second);
  }

  /// Adds a LEFT JOIN whose ON condition compares a column with a value.
  QueryBuilder leftJoinWhere(
    String targetTable,
    String first,
    String comparator,
    Object? second,
  ) {
    return _joinWithValue('left', targetTable, first, comparator, second);
  }

  /// Adds a RIGHT JOIN whose ON condition compares a column with a value.
  QueryBuilder rightJoinWhere(
    String targetTable,
    String first,
    String comparator,
    Object? second,
  ) {
    return _joinWithValue('right', targetTable, first, comparator, second);
  }

  QueryBuilder _joinWithValue(
    String type,
    String targetTable,
    String first,
    String comparator,
    Object? value,
  ) {
    final joinClause = JoinClause(_laconic);
    joinClause.where(first, value, comparator: comparator);
    _joins.add({
      'type': type,
      'table': targetTable,
      'conditions': joinClause.conditions,
    });
    return this;
  }

  /// Adds a JOIN against a derived table.
  ///
  /// [second] is a column name unless [where] is true, in which case it is a
  /// bound value.
  QueryBuilder joinSub(
    Object query,
    String as,
    String first,
    String comparator,
    Object? second, {
    String type = 'inner',
    bool where = false,
  }) {
    final compiled = _compileSubquery(query);
    final joinClause = JoinClause(_laconic);
    if (where) {
      joinClause.where(first, second, comparator: comparator);
    } else {
      if (second is! String) {
        throw LaconicException('joinSub expects a column name as second');
      }
      joinClause.on(first, second, comparator: comparator);
    }
    _joins.add({
      'type': type,
      'table': '(${compiled.sql}) as $as',
      'tableBindings': compiled.bindings,
      'conditions': joinClause.conditions,
    });
    return this;
  }

  /// Adds a LEFT JOIN against a derived table.
  QueryBuilder leftJoinSub(
    Object query,
    String as,
    String first,
    String comparator,
    Object? second, {
    bool where = false,
  }) {
    return joinSub(
      query,
      as,
      first,
      comparator,
      second,
      type: 'left',
      where: where,
    );
  }

  /// Adds a RIGHT JOIN against a derived table.
  QueryBuilder rightJoinSub(
    Object query,
    String as,
    String first,
    String comparator,
    Object? second, {
    bool where = false,
  }) {
    return joinSub(
      query,
      as,
      first,
      comparator,
      second,
      type: 'right',
      where: where,
    );
  }

  /// Adds a LATERAL JOIN against a derived table.
  QueryBuilder joinLateral(Object query, String as, {String type = 'inner'}) {
    if (type != 'inner' && type != 'left') {
      throw LaconicException('joinLateral supports inner or left joins');
    }
    final compiled = _compileSubquery(query);
    _joins.add({
      'type': 'lateral',
      'joinType': type,
      'table': '(${compiled.sql}) as $as',
      'tableBindings': compiled.bindings,
      'conditions': <Map<String, dynamic>>[],
    });
    return this;
  }

  /// Adds a LEFT LATERAL JOIN against a derived table.
  QueryBuilder leftJoinLateral(Object query, String as) {
    return joinLateral(query, as, type: 'left');
  }

  /// Adds a CROSS JOIN against a derived table.
  QueryBuilder crossJoinSub(Object query, String as) {
    final compiled = _compileSubquery(query);
    _joins.add({
      'type': 'cross',
      'table': '(${compiled.sql}) as $as',
      'tableBindings': compiled.bindings,
      'conditions': <Map<String, dynamic>>[],
    });
    return this;
  }

  /// Sets the table for this query (useful for subqueries and EXISTS clauses).
  QueryBuilder from(String table) {
    _table = table;
    _fromSubquery = null;
    _fromAlias = null;
    _indexHints.clear();
    return this;
  }

  /// Sets a derived table as the FROM source.
  QueryBuilder fromSub(Object query, String as) {
    _fromSubquery = _compileSubquery(query);
    _fromAlias = as;
    _indexHints.clear();
    return this;
  }

  /// Sets a raw FROM expression with optional bindings.
  QueryBuilder fromRaw(String sql, [List<Object?> bindings = const []]) {
    _fromSubquery = CompiledQuery(sql: sql, bindings: bindings);
    _fromAlias = null;
    _indexHints.clear();
    return this;
  }

  static final RegExp _indexNamePattern = RegExp(r'^[A-Za-z0-9_$]+$');

  /// Adds a MySQL `USE INDEX` hint.
  QueryBuilder useIndex(String index) => _addIndexHint('use', index);

  /// Adds a MySQL `FORCE INDEX` hint.
  QueryBuilder forceIndex(String index) => _addIndexHint('force', index);

  /// Adds a MySQL `IGNORE INDEX` hint.
  QueryBuilder ignoreIndex(String index) => _addIndexHint('ignore', index);

  QueryBuilder _addIndexHint(String type, String index) {
    final names = index.split(',').map((name) => name.trim()).toList();
    if (names.isEmpty ||
        names.any((name) => !_indexNamePattern.hasMatch(name))) {
      throw LaconicException('Invalid index name: "$index"');
    }
    _indexHints.add({'type': type, 'index': names.join(', ')});
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

  /// Updates the row matching [attributes], or inserts a new row when none
  /// exists. [values] are applied on update and merged into the inserted row.
  Future<bool> updateOrInsert(
    Map<String, Object?> attributes, [
    Map<String, Object?> values = const {},
  ]) async {
    if (attributes.isEmpty) {
      throw LaconicException('updateOrInsert requires non-empty attributes');
    }

    final matches = clone();
    for (final entry in attributes.entries) {
      matches.where(entry.key, entry.value);
    }

    if (await matches.exists()) {
      if (values.isNotEmpty) {
        await matches.update(values);
      }
    } else {
      await insert([
        {...attributes, ...values},
      ]);
    }
    return true;
  }

  /// Adds a `FOR UPDATE` lock to the query.
  QueryBuilder lockForUpdate() {
    _locks.add({'type': 'for_update'});
    return this;
  }

  /// Returns the current LIMIT value, if any.
  int? getLimit() => _limit;

  /// Returns the current OFFSET value, if any.
  int? getOffset() => _offset;

  /// Adds a `FOR SHARE` (PG) / `LOCK IN SHARE MODE` (MySQL) lock.
  QueryBuilder sharedLock() {
    _locks.add({'type': 'for_share'});
    return this;
  }

  static final RegExp _lockPattern = RegExp(
    r'^(for (update|share|key share|no key update)|lock in share mode)'
    r'( nowait| skip locked)?$',
  );

  /// Adds a locking clause.
  ///
  /// [value] may be `true` (FOR UPDATE), `false` (FOR SHARE), or a raw clause
  /// such as `'for update nowait'`.
  QueryBuilder lock(Object value) {
    if (value == true) return lockForUpdate();
    if (value == false) return sharedLock();
    if (value is! String) {
      throw LaconicException('lock() expects a bool or a lock clause string');
    }
    final normalized = value.trim().toLowerCase();
    if (!_lockPattern.hasMatch(normalized)) {
      throw LaconicException('Invalid lock clause: "$value"');
    }
    _locks.add({'type': 'raw', 'value': normalized});
    return this;
  }

  /// Adds a UNION clause, or UNION ALL when [all] is true.
  ///
  /// [query] may be a callback receiving a fresh builder, or an existing
  /// [QueryBuilder]. Ordering, limit and offset on this builder apply to the
  /// complete union; clauses inside a callback apply only to that branch.
  QueryBuilder union(Object query, {bool all = false}) {
    if (query is! void Function(QueryBuilder) && query is! QueryBuilder) {
      throw LaconicException('union expects a callback or a QueryBuilder');
    }
    final compiled = _compileSubquery(query);
    _unions.add({
      'sql': compiled.sql,
      'bindings': compiled.bindings,
      'all': all,
    });
    return this;
  }

  /// Adds a UNION ALL clause.
  QueryBuilder unionAll(Object query) {
    return union(query, all: true);
  }

  CompiledQuery _compileSubquery(Object query) {
    if (query is void Function(QueryBuilder)) {
      final sub = QueryBuilder(laconic: _laconic, table: '');
      query(sub);
      return sub._compileSelect();
    }
    if (query is QueryBuilder) {
      return query._compileSelect();
    }
    throw LaconicException('Expected a callback or QueryBuilder');
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

  /// Orders by the position of [column] values in [values].
  ///
  /// Values not present in [values] sort after the listed ones.
  QueryBuilder inOrderOf(String column, List<Object?> values) {
    if (values.isEmpty) {
      return this;
    }
    final clauses = <String>[];
    for (var i = 0; i < values.length; i++) {
      clauses.add('when ? then $i');
    }
    return orderByRaw(
      'case $column ${clauses.join(' ')} else ${values.length} end',
      values,
    );
  }

  /// Orders by `created_at` descending (most recent first).
  QueryBuilder latest({String column = 'created_at'}) {
    return orderBy(column, direction: 'desc');
  }

  /// Orders by `created_at` ascending (oldest first).
  QueryBuilder oldest({String column = 'created_at'}) {
    return orderBy(column, direction: 'asc');
  }

  /// Orders results in random order using the dialect's random function.
  QueryBuilder inRandomOrder() {
    return orderByRaw(_grammar.randomOrderExpression);
  }

  /// Removes all previously set ORDER BY clauses, optionally replacing them
  /// with a new ordering.
  ///
  /// Mirrors Laravel's `reorder($column, $direction)`; call [reorder] with no
  /// arguments to only clear the existing ordering.
  QueryBuilder reorder([String? column, String direction = 'asc']) {
    _orders.clear();
    if (column != null) {
      orderBy(column, direction: direction);
    }
    return this;
  }

  /// Removes all previously set ORDER BY clauses and orders by [column] desc.
  QueryBuilder reorderDesc(String column) {
    return reorder(column, 'desc');
  }

  /// Alias for [offset]. Skips the specified number of records.
  QueryBuilder skip(int count) {
    return offset(count);
  }

  /// Alias for [limit]. Takes the specified number of records.
  QueryBuilder take(int count) {
    return limit(count);
  }

  /// Limits the number of rows per partition of [column].
  ///
  /// Implemented with `row_number() over (partition by column ...)`.
  QueryBuilder groupLimit(int value, String column) {
    if (value < 0) {
      throw LaconicException('groupLimit must be zero or greater');
    }
    _groupLimit = {'value': value, 'column': column};
    return this;
  }

  /// Sets LIMIT and OFFSET for a given page number (1-indexed).
  QueryBuilder forPage(int page, {int perPage = 15}) {
    return limit(perPage).offset((page - 1) * perPage);
  }

  /// Constrains to the page after [lastId] using keyset pagination.
  ///
  /// When [lastId] is `null`, rows with a NULL [column] are excluded instead
  /// of being compared.
  QueryBuilder forPageAfterId(
    int perPage, [
    Object? lastId = 0,
    String column = 'id',
  ]) {
    _orders.removeWhere(
      (order) => order['type'] != 'raw' && order['column'] == column,
    );
    if (lastId == null) {
      whereNotNull(column);
    } else {
      where(column, lastId, comparator: '>');
    }
    return orderBy(column).limit(perPage);
  }

  /// Constrains to the page before [lastId] using keyset pagination.
  ///
  /// When [lastId] is `null`, rows with a NULL [column] are excluded instead
  /// of being compared.
  QueryBuilder forPageBeforeId(
    int perPage, [
    Object? lastId = 0,
    String column = 'id',
  ]) {
    _orders.removeWhere(
      (order) => order['type'] != 'raw' && order['column'] == column,
    );
    if (lastId == null) {
      whereNotNull(column);
    } else {
      where(column, lastId, comparator: '<');
    }
    return orderByDesc(column).limit(perPage);
  }

  /// Returns a page of results together with the total row count.
  Future<LaconicPage> paginate(int page, {int perPage = 15}) async {
    _validatePage(page, perPage);
    final total = await clone().count();
    final lastPage = total == 0 ? 1 : (total + perPage - 1) ~/ perPage;
    final data = await clone().forPage(page, perPage: perPage).get();
    return LaconicPage(
      data: data,
      total: total,
      perPage: perPage,
      currentPage: page,
      lastPage: lastPage,
    );
  }

  /// Returns a page of results and whether more pages exist, without a total.
  Future<LaconicSimplePage> simplePaginate(int page, {int perPage = 15}) async {
    _validatePage(page, perPage);
    final rows =
        await clone().limit(perPage + 1).offset((page - 1) * perPage).get();
    final hasMorePages = rows.length > perPage;
    final data = hasMorePages ? rows.sublist(0, perPage) : rows;
    return LaconicSimplePage(
      data: data,
      perPage: perPage,
      currentPage: page,
      hasMorePages: hasMorePages,
    );
  }

  /// Returns a keyset-paginated page ordered by [column].
  ///
  /// [cursor] is the last value from the previous page. The cursor column must
  /// be part of the selected columns.
  Future<LaconicCursorPage> cursorPaginate(
    int perPage, {
    String column = 'id',
    Object? cursor,
  }) async {
    if (perPage < 1) {
      throw LaconicException('perPage must be greater than zero');
    }
    final q = clone()..reorder();
    q._offset = null;
    if (cursor != null && q._unions.isEmpty) {
      final conditions = List<Map<String, dynamic>>.of(q._wheres);
      q._wheres.clear();
      if (conditions.isNotEmpty) {
        q._wheres.add({
          'type': 'nested',
          'conditions': conditions,
          'boolean': 'and',
        });
      }
      q.where(column, cursor, comparator: '>');
    }
    q.orderBy(column).limit(perPage + 1);
    final compiled = q._compileSelect(
      unionWheres: [
        if (cursor != null && q._unions.isNotEmpty)
          {
            'type': 'basic',
            'column': column,
            'comparator': '>',
            'value': cursor,
            'boolean': 'and',
          },
      ],
    );
    final rows = await _laconic.select(compiled.sql, compiled.bindings);
    final hasMorePages = rows.length > perPage;
    final data = hasMorePages ? rows.sublist(0, perPage) : rows;

    Object? nextCursor;
    if (hasMorePages && data.isNotEmpty) {
      try {
        nextCursor = data.last[column];
      } on ArgumentError {
        throw LaconicException(
          'cursorPaginate requires selecting the cursor column "$column"',
        );
      }
      if (nextCursor == null) {
        throw LaconicException('Cursor column must be non-null and advance');
      }
    }

    return LaconicCursorPage(
      data: data,
      perPage: perPage,
      nextCursor: nextCursor,
      hasMorePages: hasMorePages,
    );
  }

  /// Number of rows used by pagination.
  Future<int> getCountForPagination() => count();

  void _validatePage(int page, int perPage) {
    if (page < 1) {
      throw LaconicException('Page must be greater than zero');
    }
    if (perPage < 1) {
      throw LaconicException('perPage must be greater than zero');
    }
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
    final operator = validateOperator(comparator);

    if (value == null &&
        (operator == '=' || operator == '!=' || operator == '<>')) {
      return operator == '=' ? orWhereNull(column) : orWhereNotNull(column);
    }

    if (value is void Function(QueryBuilder) || value is QueryBuilder) {
      final compiled = _compileSubquery(value as Object);
      _wheres.add({
        'type': 'subquery',
        'column': column,
        'comparator': operator,
        'sql': compiled.sql,
        'bindings': compiled.bindings,
        'boolean': 'or',
      });
      return this;
    }

    _wheres.add({
      'type': 'basic',
      'column': column,
      'comparator': operator,
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds an OR WHERE NOT EQUAL condition, or negates a nested group when
  /// passed a `void Function(QueryBuilder)` callback.
  ///
  /// Example:
  /// ```dart
  /// query.orWhereNot((q) => q.where('a', 1).orWhere('b', 2));
  /// // SQL: OR NOT (a = ? OR b = ?)
  /// ```
  QueryBuilder orWhereNot(Object column, [Object? value]) {
    if (column is void Function(QueryBuilder)) {
      return _nestedWhere(column, 'or', not: true);
    }
    if (column is! String) {
      throw LaconicException('whereNot expects a column name or a callback');
    }
    return orWhere(column, value, comparator: '!=');
  }

  /// Adds an OR WHERE LIKE condition.
  ///
  /// Pass `caseSensitive: false` for a case-insensitive comparison.
  QueryBuilder orWhereLike(
    String column,
    Object? value, {
    bool caseSensitive = true,
  }) {
    if (caseSensitive) {
      return orWhere(column, value, comparator: 'like');
    }
    _wheres.add({
      'type': 'like',
      'column': column,
      'value': value,
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds an OR WHERE NOT LIKE condition.
  ///
  /// Pass `caseSensitive: false` for a case-insensitive comparison.
  QueryBuilder orWhereNotLike(
    String column,
    Object? value, {
    bool caseSensitive = true,
  }) {
    if (caseSensitive) {
      return orWhere(column, value, comparator: 'not like');
    }
    _wheres.add({
      'type': 'like',
      'column': column,
      'value': value,
      'boolean': 'or',
      'not': true,
    });
    return this;
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
    String boolean, {
    bool not = false,
  }) {
    final nested = QueryBuilder(laconic: _laconic, table: _table);
    callback(nested);
    if (nested._wheres.isEmpty) {
      return this;
    }
    _wheres.add({
      'type': 'nested',
      'conditions': nested._wheres,
      'boolean': boolean,
      'not': not,
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

  /// Compiles an EXISTS subquery, preserving filters, groups and pagination.
  ///
  /// Used by [JoinClause] and the WHERE EXISTS methods.
  CompiledQuery compileAsSubquery() => _compileExistence();

  CompiledQuery _compileExistence({bool limitToOne = false}) {
    final query = clone()..reorder();
    if (limitToOne) query._limit = _limit == 0 ? 0 : 1;
    if (_unions.isEmpty &&
        !_distinct &&
        _columns.length == 1 &&
        _columns.first == '*') {
      if (_groups.isNotEmpty) {
        query._columns = List.of(_groups);
      } else if (_havings.isEmpty) {
        query._columns = ['1'];
      }
    }
    return query._compileSelect();
  }

  /// Processes query results in chunks to avoid memory issues.
  Stream<List<LaconicResult>> _chunkStream(int count) async* {
    if (count <= 0) throw LaconicException('Chunk size must be positive');
    var page = 1;
    while (true) {
      final results = await clone().forPage(page, perPage: count).get();
      if (results.isEmpty) break;
      final received = results.length;
      yield results;
      if (received < count) break;
      page++;
    }
  }

  /// Processes query results in chunks to avoid memory issues.
  Future<void> chunk(
    int count,
    Future<void> Function(List<LaconicResult>) callback,
  ) async {
    await for (final results in _chunkStream(count)) {
      await callback(results);
    }
  }

  /// Streams results one row at a time using offset-based chunking.
  ///
  /// Add an ordering clause for stable pagination; otherwise the database may
  /// return rows in a different order between chunks.
  Stream<LaconicResult> lazy([int count = 1000]) async* {
    await for (final results in _chunkStream(count)) {
      for (final row in results) {
        yield row;
      }
    }
  }

  /// Streams rows using the driver's native cursor when available.
  Stream<LaconicResult> cursor() {
    final compiled = _compileSelect();
    return _laconic.selectStream(compiled.sql, compiled.bindings);
  }

  /// Processes results in ascending order of a unique, non-null cursor column.
  ///
  /// Replaces existing ordering with [column]. An existing offset applies only
  /// to the first page. [alias] optionally qualifies the column with a table alias.
  Stream<List<LaconicResult>> _chunkByIdStream(
    int count, {
    String column = 'id',
    String? alias,
  }) async* {
    if (count <= 0) throw LaconicException('Chunk size must be positive');
    final col = alias != null ? '$alias.$column' : column;
    final resultColumn = column.split('.').last;
    Object? lastId;
    while (true) {
      final q = clone()..reorder();
      if (lastId != null && _unions.isEmpty) {
        final conditions = List<Map<String, dynamic>>.of(q._wheres);
        q._wheres.clear();
        if (conditions.isNotEmpty) {
          q._wheres.add({
            'type': 'nested',
            'conditions': conditions,
            'boolean': 'and',
          });
        }
        q.where(col, lastId, comparator: '>');
      }
      if (lastId != null) q._offset = null;
      q.orderBy(_unions.isEmpty ? col : resultColumn).limit(count);
      final compiled = q._compileSelect(
        unionWheres: [
          if (lastId != null)
            {
              'type': 'basic',
              'column': resultColumn,
              'comparator': '>',
              'value': lastId,
              'boolean': 'and',
            },
        ],
      );
      final results = await _laconic.select(compiled.sql, compiled.bindings);
      if (results.isEmpty) break;
      final nextId = results.last[resultColumn];
      if (nextId == null || nextId == lastId) {
        throw LaconicException('Chunk cursor must be non-null and advance');
      }
      lastId = nextId;
      final received = results.length;
      yield results;
      if (received < count) break;
    }
  }

  /// Processes results in ascending order of a unique, non-null cursor column.
  ///
  /// Replaces existing ordering with [column]. An existing offset applies only
  /// to the first page. [alias] optionally qualifies the column with a table alias.
  Future<void> chunkById(
    int count,
    Future<void> Function(List<LaconicResult>) callback, {
    String column = 'id',
    String? alias,
  }) async {
    await for (final results in _chunkByIdStream(
      count,
      column: column,
      alias: alias,
    )) {
      await callback(results);
    }
  }

  /// Streams rows ordered by a unique, non-null cursor column.
  Stream<LaconicResult> lazyById([
    int count = 1000,
    String column = 'id',
    String? alias,
  ]) async* {
    await for (final results in _chunkByIdStream(
      count,
      column: column,
      alias: alias,
    )) {
      for (final row in results) {
        yield row;
      }
    }
  }

  /// Iterates over each result using cursor-based chunking.
  Future<void> eachById(
    Future<void> Function(LaconicResult) callback, {
    int count = 1000,
    String column = 'id',
    String? alias,
  }) async {
    await for (final row in lazyById(count, column, alias)) {
      await callback(row);
    }
  }

  /// Iterates over each result using chunking.
  Future<void> each(
    Future<void> Function(LaconicResult) callback, {
    int count = 1000,
  }) async {
    await chunk(count, (results) async {
      for (final row in results) {
        await callback(row);
      }
    });
  }

  /// Returns a deep copy of this QueryBuilder for reuse.
  QueryBuilder clone() {
    final copy =
        QueryBuilder(laconic: _laconic, table: _table)
          .._columns = List<String>.from(_columns)
          .._selectBindings.addAll(_selectBindings)
          .._groupBindings.addAll(_groupBindings)
          .._fromSubquery = _fromSubquery
          .._fromAlias = _fromAlias
          .._indexHints.addAll(
            _indexHints.map((hint) => Map<String, String>.from(hint)),
          )
          .._wheres.addAll(_wheres.map(_deepCopyWhere))
          .._joins.addAll(_joins.map(_deepCopyJoin))
          .._orders.addAll(_orders.map((o) => Map<String, dynamic>.from(o)))
          .._groups.addAll(_groups)
          .._havings.addAll(_havings.map((h) => Map<String, dynamic>.from(h)))
          .._distinct = _distinct
          .._distinctOn = _distinctOn
          .._groupLimit =
              _groupLimit == null
                  ? null
                  : Map<String, dynamic>.from(_groupLimit!)
          .._limit = _limit
          .._offset = _offset
          .._locks.addAll(_locks.map((l) => Map<String, dynamic>.from(l)))
          .._unions.addAll(_unions.map((u) => Map<String, dynamic>.from(u)));
    return copy;
  }

  /// Deep-copies a WHERE condition map, recursively copying nested conditions.
  static Map<String, dynamic> _deepCopyWhere(Map<String, dynamic> where) {
    final copy = Map<String, dynamic>.from(where);
    if (copy['type'] == 'nested') {
      copy['conditions'] =
          (copy['conditions'] as List)
              .map((c) => _deepCopyWhere(Map<String, dynamic>.from(c)))
              .toList();
    }
    return copy;
  }

  /// Deep-copies a JOIN condition map, recursively copying nested conditions.
  static Map<String, dynamic> _deepCopyJoin(Map<String, dynamic> join) {
    final copy = Map<String, dynamic>.from(join);
    final conditions = copy['conditions'] as List<Map<String, dynamic>>?;
    if (conditions != null) {
      copy['conditions'] =
          conditions.map((c) => Map<String, dynamic>.from(c)).toList();
    }
    final tableBindings = copy['tableBindings'];
    if (tableBindings is List) {
      copy['tableBindings'] = List<Object?>.from(tableBindings);
    }
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
    _selectBindings.clear();
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
      _selectBindings.clear();
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
  /// query.selectRaw('case when active = ? then 1 else 0 end as active', [1]);
  /// ```
  QueryBuilder selectRaw(String sql, [List<Object?> bindings = const []]) {
    if (_columns.length == 1 && _columns[0] == '*') {
      _columns = [sql];
      _selectBindings.clear();
    } else {
      _columns.add(sql);
    }
    _selectBindings.addAll(bindings);
    return this;
  }

  /// Adds a subquery to the SELECT clause as `(subquery) as as`.
  QueryBuilder selectSub(Object query, String as) {
    final compiled = _grammar.compileInlineSubquery(_compileSubquery(query));
    final sql = '(${compiled.sql}) as $as';
    if (_columns.length == 1 && _columns[0] == '*') {
      _columns = [sql];
      _selectBindings.clear();
    } else {
      _columns.add(sql);
    }
    _selectBindings.addAll(compiled.bindings);
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
    final compiled = _compileSelect(limitOverride: 2);

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

  /// Returns a single column value from the only matching row.
  ///
  /// Throws [LaconicException] when no row or more than one row matches.
  Future<Object?> soleValue(String column) async {
    final row = await sole();
    return row[column];
  }

  /// Updates records matching the query.
  ///
  /// [data] is a map of column-value pairs to update. Must be non-empty.
  /// Returns the number of affected rows reported by the database.
  Future<int> update(Map<String, Object?> data) async {
    if (data.isEmpty) {
      throw LaconicException('Cannot update with an empty data map');
    }
    final compiled = _grammar.compileUpdate(
      table: _table,
      data: data,
      wheres: _wheres,
    );

    return _laconic.affectingStatement(compiled.sql, compiled.bindings);
  }

  /// Adds a WHERE condition to the query.
  ///
  /// [column] is the column name.
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  QueryBuilder where(String column, Object? value, {String comparator = '='}) {
    final operator = validateOperator(comparator);

    // Laravel converts a `null` comparison with =, != or <> into IS NULL /
    // IS NOT NULL instead of emitting a comparison that can never match.
    if (value == null &&
        (operator == '=' || operator == '!=' || operator == '<>')) {
      return operator == '=' ? whereNull(column) : whereNotNull(column);
    }

    if (value is void Function(QueryBuilder) || value is QueryBuilder) {
      final compiled = _compileSubquery(value as Object);
      _wheres.add({
        'type': 'subquery',
        'column': column,
        'comparator': operator,
        'sql': compiled.sql,
        'bindings': compiled.bindings,
        'boolean': 'and',
      });
      return this;
    }

    _wheres.add({
      'type': 'basic',
      'column': column,
      'comparator': operator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds a WHERE NOT EQUAL condition (shorthand), or negates a nested group
  /// when passed a `void Function(QueryBuilder)` callback.
  ///
  /// Example:
  /// ```dart
  /// query.whereNot((q) => q.where('a', 1).orWhere('b', 2));
  /// // SQL: NOT (a = ? OR b = ?)
  /// ```
  QueryBuilder whereNot(Object column, [Object? value]) {
    if (column is void Function(QueryBuilder)) {
      return _nestedWhere(column, 'and', not: true);
    }
    if (column is! String) {
      throw LaconicException('whereNot expects a column name or a callback');
    }
    return where(column, value, comparator: '!=');
  }

  /// Adds a WHERE LIKE condition (shorthand).
  ///
  /// Pass `caseSensitive: false` for a case-insensitive comparison. The
  /// default is `true` to preserve the database's native LIKE behavior;
  /// Laravel defaults to case-insensitive.
  QueryBuilder whereLike(
    String column,
    Object? value, {
    bool caseSensitive = true,
  }) {
    if (caseSensitive) {
      return where(column, value, comparator: 'like');
    }
    _wheres.add({
      'type': 'like',
      'column': column,
      'value': value,
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds a WHERE NOT LIKE condition (shorthand).
  ///
  /// Pass `caseSensitive: false` for a case-insensitive comparison.
  QueryBuilder whereNotLike(
    String column,
    Object? value, {
    bool caseSensitive = true,
  }) {
    if (caseSensitive) {
      return where(column, value, comparator: 'not like');
    }
    _wheres.add({
      'type': 'like',
      'column': column,
      'value': value,
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds AND-ed equality conditions from [values].
  ///
  /// This is the Dart-friendly equivalent of Laravel's `where([...])`; Dart
  /// cannot overload [where] with both a named comparator and a Map.
  QueryBuilder whereMap(Map<String, Object?> values) {
    for (final entry in values.entries) {
      where(entry.key, entry.value);
    }
    return this;
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
      'comparator': validateOperator(comparator),
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
      'comparator': validateOperator(comparator),
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
      'comparator': validateOperator(comparator),
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
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR WHERE clause where no column should match the given value.
  QueryBuilder orWhereNone(
    List<String> columns,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'none',
      'columns': columns,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'or',
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
  QueryBuilder whereIn(String column, Object values) {
    return _addIn(column, values, 'and', false);
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
  QueryBuilder whereNotIn(String column, Object values) {
    return _addIn(column, values, 'and', true);
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
      'comparator': validateOperator(comparator),
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
  QueryBuilder orWhereIn(String column, Object values) {
    return _addIn(column, values, 'or', false);
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
  QueryBuilder orWhereNotIn(String column, Object values) {
    return _addIn(column, values, 'or', true);
  }

  QueryBuilder _addIn(String column, Object values, String boolean, bool not) {
    if (values is List) {
      _wheres.add({
        'type': 'in',
        'column': column,
        'values': List<Object?>.from(values),
        'boolean': boolean,
        'not': not,
      });
      return this;
    }

    final compiled = _compileSubquery(values);
    _wheres.add({
      'type': 'inSubquery',
      'column': column,
      'sql': compiled.sql,
      'bindings': compiled.bindings,
      'boolean': boolean,
      'not': not,
    });
    return this;
  }

  /// Adds a WHERE IN condition whose integer values are interpolated directly
  /// instead of being bound, mirroring Laravel's `whereIntegerInRaw`.
  QueryBuilder whereIntegerInRaw(String column, List<int> values) {
    _wheres.add({
      'type': 'integerInRaw',
      'column': column,
      'values': values,
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds an OR WHERE IN condition with interpolated integer values.
  QueryBuilder orWhereIntegerInRaw(String column, List<int> values) {
    _wheres.add({
      'type': 'integerInRaw',
      'column': column,
      'values': values,
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds a WHERE NOT IN condition with interpolated integer values.
  QueryBuilder whereIntegerNotInRaw(String column, List<int> values) {
    _wheres.add({
      'type': 'integerInRaw',
      'column': column,
      'values': values,
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds an OR WHERE NOT IN condition with interpolated integer values.
  QueryBuilder orWhereIntegerNotInRaw(String column, List<int> values) {
    _wheres.add({
      'type': 'integerInRaw',
      'column': column,
      'values': values,
      'boolean': 'or',
      'not': true,
    });
    return this;
  }

  /// Adds a row-value comparison such as `(a, b) = (?, ?)`.
  QueryBuilder whereRowValues(
    List<String> columns,
    String operator,
    List<Object?> values,
  ) {
    if (columns.isEmpty || columns.length != values.length) {
      throw LaconicException(
        'The number of columns must match the number of values',
      );
    }
    _wheres.add({
      'type': 'rowValues',
      'columns': columns,
      'operator': validateOperator(operator),
      'values': values,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR row-value comparison such as `(a, b) = (?, ?)`.
  QueryBuilder orWhereRowValues(
    List<String> columns,
    String operator,
    List<Object?> values,
  ) {
    if (columns.isEmpty || columns.length != values.length) {
      throw LaconicException(
        'The number of columns must match the number of values',
      );
    }
    _wheres.add({
      'type': 'rowValues',
      'columns': columns,
      'operator': validateOperator(operator),
      'values': values,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds `? BETWEEN column1 AND column2`, comparing a bound value against
  /// two columns.
  QueryBuilder whereValueBetween(Object? value, List<String> columns) {
    return _addValueBetween(value, columns, 'and', false);
  }

  /// Adds an OR `? BETWEEN column1 AND column2` condition.
  QueryBuilder orWhereValueBetween(Object? value, List<String> columns) {
    return _addValueBetween(value, columns, 'or', false);
  }

  /// Adds `? NOT BETWEEN column1 AND column2`.
  QueryBuilder whereValueNotBetween(Object? value, List<String> columns) {
    return _addValueBetween(value, columns, 'and', true);
  }

  /// Adds an OR `? NOT BETWEEN column1 AND column2` condition.
  QueryBuilder orWhereValueNotBetween(Object? value, List<String> columns) {
    return _addValueBetween(value, columns, 'or', true);
  }

  QueryBuilder _addValueBetween(
    Object? value,
    List<String> columns,
    String boolean,
    bool not,
  ) {
    if (columns.length != 2) {
      throw LaconicException('whereValueBetween requires exactly two columns');
    }
    _wheres.add({
      'type': 'valueBetween',
      'value': value,
      'columns': columns,
      'boolean': boolean,
      'not': not,
    });
    return this;
  }

  /// Adds a null-safe equality comparison.
  ///
  /// Compiles to `IS NOT DISTINCT FROM` on PostgreSQL, `<=>` on MySQL and
  /// `IS` on SQLite, so `NULL` matches `NULL`.
  QueryBuilder whereNullSafeEquals(String column, Object? value) {
    _wheres.add({
      'type': 'nullSafeEquals',
      'column': column,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR null-safe equality comparison.
  QueryBuilder orWhereNullSafeEquals(String column, Object? value) {
    _wheres.add({
      'type': 'nullSafeEquals',
      'column': column,
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a case-sensitive binary comparison. MySQL only.
  QueryBuilder whereBinary(String column, Object? value) {
    return _addBinary(column, value, 'and', false);
  }

  /// Adds a case-sensitive binary non-equality comparison. MySQL only.
  QueryBuilder whereNotBinary(String column, Object? value) {
    return _addBinary(column, value, 'and', true);
  }

  /// Adds an OR case-sensitive binary comparison. MySQL only.
  QueryBuilder orWhereBinary(String column, Object? value) {
    return _addBinary(column, value, 'or', false);
  }

  /// Adds an OR case-sensitive binary non-equality comparison. MySQL only.
  QueryBuilder orWhereNotBinary(String column, Object? value) {
    return _addBinary(column, value, 'or', true);
  }

  QueryBuilder _addBinary(
    String column,
    Object? value,
    String boolean,
    bool not,
  ) {
    _wheres.add({
      'type': 'binary',
      'column': column,
      'value': value,
      'boolean': boolean,
      'not': not,
    });
    return this;
  }

  /// Adds a JSON containment condition.
  ///
  /// MySQL and PostgreSQL compare the encoded [value] against the JSON column;
  /// SQLite checks array elements through `json_each`.
  QueryBuilder whereJsonContains(String column, Object? value) {
    return _addJsonContains(column, value, 'and', false);
  }

  /// Adds a JSON non-containment condition.
  QueryBuilder whereJsonDoesntContain(String column, Object? value) {
    return _addJsonContains(column, value, 'and', true);
  }

  /// Adds an OR JSON containment condition.
  QueryBuilder orWhereJsonContains(String column, Object? value) {
    return _addJsonContains(column, value, 'or', false);
  }

  /// Adds an OR JSON non-containment condition.
  QueryBuilder orWhereJsonDoesntContain(String column, Object? value) {
    return _addJsonContains(column, value, 'or', true);
  }

  QueryBuilder _addJsonContains(
    String column,
    Object? value,
    String boolean,
    bool not,
  ) {
    final split = _splitJsonColumn(column);
    _wheres.add({
      'type': 'jsonContains',
      'column': split.column,
      'path': split.path,
      'value': value,
      'boolean': boolean,
      'not': not,
    });
    return this;
  }

  /// Adds a JSON key-existence condition.
  ///
  /// The path may be given as `payload->name` or as the optional [path]
  /// argument, but not both.
  QueryBuilder whereJsonContainsKey(String column, [String? path]) {
    return _addJsonContainsKey(column, path, 'and', false);
  }

  /// Adds a JSON key-absence condition.
  QueryBuilder whereJsonDoesntContainKey(String column, [String? path]) {
    return _addJsonContainsKey(column, path, 'and', true);
  }

  /// Adds an OR JSON key-existence condition.
  QueryBuilder orWhereJsonContainsKey(String column, [String? path]) {
    return _addJsonContainsKey(column, path, 'or', false);
  }

  /// Adds an OR JSON key-absence condition.
  QueryBuilder orWhereJsonDoesntContainKey(String column, [String? path]) {
    return _addJsonContainsKey(column, path, 'or', true);
  }

  QueryBuilder _addJsonContainsKey(
    String column,
    String? path,
    String boolean,
    bool not,
  ) {
    final split = _splitJsonColumn(column);
    if (split.path != null && path != null) {
      throw LaconicException(
        'Specify the JSON path in the column or as an argument, not both',
      );
    }
    final effectivePath =
        split.path ?? (path == null ? null : _normalizeJsonPath(path));
    if (effectivePath == null || effectivePath == r'$') {
      throw LaconicException('JSON key conditions require a path');
    }
    _wheres.add({
      'type': 'jsonContainsKey',
      'column': split.column,
      'path': effectivePath,
      'boolean': boolean,
      'not': not,
    });
    return this;
  }

  /// Adds a JSON length condition.
  QueryBuilder whereJsonLength(
    String column,
    int value, {
    String comparator = '=',
    String? path,
  }) {
    return _addJsonLength(column, value, 'and', comparator, path);
  }

  /// Adds an OR JSON length condition.
  QueryBuilder orWhereJsonLength(
    String column,
    int value, {
    String comparator = '=',
    String? path,
  }) {
    return _addJsonLength(column, value, 'or', comparator, path);
  }

  QueryBuilder _addJsonLength(
    String column,
    int value,
    String boolean,
    String comparator,
    String? path,
  ) {
    final split = _splitJsonColumn(column);
    if (split.path != null && path != null) {
      throw LaconicException(
        'Specify the JSON path in the column or as an argument, not both',
      );
    }
    _wheres.add({
      'type': 'jsonLength',
      'column': split.column,
      'path': split.path ?? (path == null ? null : _normalizeJsonPath(path)),
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': boolean,
    });
    return this;
  }

  /// Adds a JSON overlap condition comparing array elements.
  QueryBuilder whereJsonOverlaps(String column, Object? value) {
    return _addJsonOverlaps(column, value, 'and', false);
  }

  /// Adds a JSON non-overlap condition.
  QueryBuilder whereJsonDoesntOverlap(String column, Object? value) {
    return _addJsonOverlaps(column, value, 'and', true);
  }

  /// Adds an OR JSON overlap condition.
  QueryBuilder orWhereJsonOverlaps(String column, Object? value) {
    return _addJsonOverlaps(column, value, 'or', false);
  }

  /// Adds an OR JSON non-overlap condition.
  QueryBuilder orWhereJsonDoesntOverlap(String column, Object? value) {
    return _addJsonOverlaps(column, value, 'or', true);
  }

  QueryBuilder _addJsonOverlaps(
    String column,
    Object? value,
    String boolean,
    bool not,
  ) {
    final split = _splitJsonColumn(column);
    _wheres.add({
      'type': 'jsonOverlaps',
      'column': split.column,
      'path': split.path,
      'value': value,
      'boolean': boolean,
      'not': not,
    });
    return this;
  }

  /// Adds a full-text search condition.
  ///
  /// MySQL modes: `boolean` or `natural language` (default).
  /// PostgreSQL modes: `plain` (default), `phrase`, `websearch` or `raw`.
  /// SQLite does not support full-text search through this method.
  QueryBuilder whereFullText(
    List<String> columns,
    String value, {
    String? mode,
    String? language,
    bool expanded = false,
  }) {
    return _addFullText(
      columns,
      value,
      'and',
      mode: mode,
      language: language,
      expanded: expanded,
    );
  }

  /// Adds an OR full-text search condition.
  QueryBuilder orWhereFullText(
    List<String> columns,
    String value, {
    String? mode,
    String? language,
    bool expanded = false,
  }) {
    return _addFullText(
      columns,
      value,
      'or',
      mode: mode,
      language: language,
      expanded: expanded,
    );
  }

  QueryBuilder _addFullText(
    List<String> columns,
    String value,
    String boolean, {
    String? mode,
    String? language,
    bool expanded = false,
  }) {
    if (columns.isEmpty) {
      throw LaconicException('whereFullText requires at least one column');
    }
    _wheres.add({
      'type': 'fullText',
      'columns': List<String>.from(columns),
      'table': _table,
      'value': value,
      'boolean': boolean,
      'options': {
        if (mode != null) 'mode': mode,
        if (language != null) 'language': language,
        'expanded': expanded,
      },
    });
    return this;
  }

  static String _normalizeJsonPath(String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith(r'$')) {
      return trimmed;
    }
    final prefix = trimmed.startsWith('.') ? r'$' : r'$.';
    return '$prefix$trimmed';
  }

  static ({String column, String? path}) _splitJsonColumn(String column) {
    final parts = column.split('->');
    if (parts.length == 1) {
      return (column: column.trim(), path: null);
    }
    final field = parts.removeAt(0).trim();
    final rawPath = parts.join('.').trim();
    return (
      column: field,
      path: rawPath.isEmpty ? null : _normalizeJsonPath(rawPath),
    );
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

  /// Adds a WHERE DATE(col) comparison (defaults to `=`).
  QueryBuilder whereDate(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'date',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR WHERE DATE(col) comparison (defaults to `=`).
  QueryBuilder orWhereDate(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'date',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a WHERE TIME(col) comparison (defaults to `=`).
  QueryBuilder whereTime(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'time',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR WHERE TIME(col) comparison (defaults to `=`).
  QueryBuilder orWhereTime(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'time',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a WHERE DAY(col) comparison (defaults to `=`).
  QueryBuilder whereDay(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'day',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR WHERE DAY(col) comparison (defaults to `=`).
  QueryBuilder orWhereDay(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'day',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a WHERE MONTH(col) comparison (defaults to `=`).
  QueryBuilder whereMonth(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'month',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR WHERE MONTH(col) comparison (defaults to `=`).
  QueryBuilder orWhereMonth(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'month',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a WHERE YEAR(col) comparison (defaults to `=`).
  QueryBuilder whereYear(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'year',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR WHERE YEAR(col) comparison (defaults to `=`).
  QueryBuilder orWhereYear(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _wheres.add({
      'type': 'date',
      'dateType': 'year',
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'or',
    });
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
      'comparator': validateOperator(comparator),
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
      'comparator': validateOperator(comparator),
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
  QueryBuilder groupByRaw(String sql, [List<Object?> bindings = const []]) {
    _groups.add(sql);
    _groupBindings.addAll(bindings);
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
      'comparator': validateOperator(comparator),
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
  QueryBuilder orHaving(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    _havings.add({
      'column': column,
      'comparator': validateOperator(comparator),
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a HAVING ... BETWEEN condition.
  QueryBuilder havingBetween(
    String column, {
    required Object? min,
    required Object? max,
  }) {
    _havings.add({
      'type': 'between',
      'column': column,
      'values': [min, max],
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds a HAVING ... NOT BETWEEN condition.
  QueryBuilder havingNotBetween(
    String column, {
    required Object? min,
    required Object? max,
  }) {
    _havings.add({
      'type': 'between',
      'column': column,
      'values': [min, max],
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds an OR HAVING ... BETWEEN condition.
  QueryBuilder orHavingBetween(
    String column, {
    required Object? min,
    required Object? max,
  }) {
    _havings.add({
      'type': 'between',
      'column': column,
      'values': [min, max],
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds an OR HAVING ... NOT BETWEEN condition.
  QueryBuilder orHavingNotBetween(
    String column, {
    required Object? min,
    required Object? max,
  }) {
    _havings.add({
      'type': 'between',
      'column': column,
      'values': [min, max],
      'boolean': 'or',
      'not': true,
    });
    return this;
  }

  /// Adds a HAVING ... IS NULL condition.
  QueryBuilder havingNull(String column) {
    _havings.add({
      'type': 'null',
      'column': column,
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds an OR HAVING ... IS NULL condition.
  QueryBuilder orHavingNull(String column) {
    _havings.add({
      'type': 'null',
      'column': column,
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds a HAVING ... IS NOT NULL condition.
  QueryBuilder havingNotNull(String column) {
    _havings.add({
      'type': 'null',
      'column': column,
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds an OR HAVING ... IS NOT NULL condition.
  QueryBuilder orHavingNotNull(String column) {
    _havings.add({
      'type': 'null',
      'column': column,
      'boolean': 'or',
      'not': true,
    });
    return this;
  }

  /// Adds a parenthesized nested HAVING group.
  QueryBuilder havingNested(void Function(QueryBuilder) callback) {
    return _nestedHaving(callback, 'and');
  }

  /// Adds an OR parenthesized nested HAVING group.
  QueryBuilder orHavingNested(void Function(QueryBuilder) callback) {
    return _nestedHaving(callback, 'or');
  }

  QueryBuilder _nestedHaving(
    void Function(QueryBuilder) callback,
    String boolean,
  ) {
    final nested = QueryBuilder(laconic: _laconic, table: _table);
    callback(nested);
    if (nested._havings.isEmpty) {
      return this;
    }
    _havings.add({
      'type': 'nested',
      'conditions': nested._havings,
      'boolean': boolean,
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
  /// Makes the query return only distinct records.
  ///
  /// Passing [columns] also selects those columns and enables PostgreSQL's
  /// `DISTINCT ON (columns)`; other dialects compile a plain `DISTINCT`.
  QueryBuilder distinct([List<String>? columns]) {
    _distinct = true;
    if (columns != null && columns.isNotEmpty) {
      _columns = columns;
      _selectBindings.clear();
      _distinctOn = true;
    } else {
      _distinctOn = false;
    }
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
    final value = await _aggregate('AVG', column);
    return value?.toDouble();
  }

  /// Returns the sum of a column's values.
  ///
  /// [column] is the column name to sum.
  ///
  /// Example:
  /// ```dart
  /// final totalVotes = await query.sum('votes');
  /// ```
  Future<num?> sum(String column) async {
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
  Future<num?> max(String column) async {
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
  Future<num?> min(String column) async {
    return _aggregate('MIN', column);
  }

  /// Helper method for aggregate functions.
  ///
  /// Preserves all query clauses. When GROUP BY is present, returns the
  /// aggregate value from the first group only. For grouped aggregates
  /// that require all group values, use [get] with [selectRaw] instead.
  Future<num?> _aggregate(String function, String column) async {
    if (_unions.isNotEmpty) {
      final query = clone()..reorder();
      query._limit = null;
      query._offset = null;
      query._locks.clear();
      final inner = query._compileSelect();
      final results = await _laconic.select(
        'select $function($column) as aggregate from (${inner.sql}) as laconic_aggregate',
        inner.bindings,
      );
      final value = results.first['aggregate'];
      return value is num ? value : num.tryParse('$value');
    }

    final compiled = _grammar.compileSelect(
      table: _table,
      columns: ['$function($column) as aggregate'],
      wheres: _wheres,
      joins: _joins,
      orders: [],
      groups: _groups,
      groupBindings: _groupBindings,
      havings: _havings,
      distinct: _distinct,
      fromSubquery: _fromSubquery,
      fromAlias: _fromAlias,
      indexHints: _indexHints,
      limit: _groups.isEmpty ? null : 1,
      offset: null,
      locks: const [],
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    if (results.isEmpty) {
      return null;
    }

    final value = results.first['aggregate'];
    if (value == null) {
      return null;
    }

    // Preserve the database's numeric type: SUM/MAX/MIN over integer columns
    // should stay integers rather than being widened to double.
    if (value is num) {
      return value;
    } else if (value is String) {
      return num.tryParse(value);
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
    final compiled = _compileExistence(limitToOne: true);
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

  /// Returns `true` when rows exist, otherwise [fallback].
  Future<bool> existsOr(bool fallback) async {
    return (await exists()) || fallback;
  }

  /// Returns `true` when no rows exist, otherwise [fallback].
  Future<bool> doesntExistOr(bool fallback) async {
    return (await doesntExist()) || fallback;
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

    final compiled = _compileSelect(columns: columns);

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

  /// Joins the values of [column] with [glue].
  Future<String> implode(String column, [String glue = '']) async {
    final values = await pluck(column) as List<Object?>;
    return values.map((value) => value == null ? '' : '$value').join(glue);
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
    final compiled = _compileSelect(columns: [column], limitOverride: 1);

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
  /// Returns the number of affected rows reported by the database.
  ///
  /// Example:
  /// ```dart
  /// await query.where('id', 1).increment('votes');
  /// await query.where('id', 1).increment('votes', amount: 5);
  /// await query.where('id', 1).increment('votes', extra: {'updated_at': DateTime.now()});
  /// ```
  Future<int> increment(
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

    return _laconic.affectingStatement(compiled.sql, compiled.bindings);
  }

  /// Decrements a column's value by a given amount.
  ///
  /// [column] is the column name to decrement.
  /// [amount] is the amount to decrement by (defaults to 1).
  /// [extra] is an optional map of additional columns to update.
  /// Returns the number of affected rows reported by the database.
  ///
  /// Example:
  /// ```dart
  /// await query.where('id', 1).decrement('votes');
  /// await query.where('id', 1).decrement('votes', amount: 5);
  /// await query.where('id', 1).decrement('votes', extra: {'updated_at': DateTime.now()});
  /// ```
  Future<int> decrement(
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

    return _laconic.affectingStatement(compiled.sql, compiled.bindings);
  }

  /// Updates rows using a `FROM` clause. PostgreSQL only.
  Future<int> updateFrom(String from, Map<String, Object?> data) async {
    if (data.isEmpty) {
      throw LaconicException('Cannot update with an empty data map');
    }
    final compiled = _grammar.compileUpdateFrom(
      table: _table,
      from: from,
      data: data,
      wheres: _wheres,
    );
    return _laconic.affectingStatement(compiled.sql, compiled.bindings);
  }

  /// Increments multiple columns in one UPDATE statement.
  Future<int> incrementEach(
    Map<String, num> columns, {
    Map<String, Object?>? extra,
    bool allowWithoutWhere = false,
  }) {
    return _adjustEach('+', columns, extra, allowWithoutWhere);
  }

  /// Decrements multiple columns in one UPDATE statement.
  Future<int> decrementEach(
    Map<String, num> columns, {
    Map<String, Object?>? extra,
    bool allowWithoutWhere = false,
  }) {
    return _adjustEach('-', columns, extra, allowWithoutWhere);
  }

  Future<int> _adjustEach(
    String operator,
    Map<String, num> columns,
    Map<String, Object?>? extra,
    bool allowWithoutWhere,
  ) async {
    if (_wheres.isEmpty && !allowWithoutWhere) {
      throw LaconicException(
        'Calling ${operator == '+' ? 'incrementEach' : 'decrementEach'}() '
        'without WHERE clause will update all records. '
        'Use allowWithoutWhere: true if this is intentional.',
      );
    }
    if (columns.isEmpty && (extra == null || extra.isEmpty)) {
      throw LaconicException('Cannot adjust an empty set of columns');
    }

    return update({
      for (final entry in columns.entries)
        entry.key: raw('${entry.key} $operator ${entry.value}'),
      ...?extra,
    });
  }

  /// Returns the compiled SQL for the current query without executing it.
  String toSql() {
    return _compileForDebug().sql;
  }

  /// Returns the parameter bindings for the current query without executing it.
  List<Object?> getBindings() {
    return _compileForDebug().bindings;
  }

  /// Returns the compiled SQL with bindings substituted inline.
  ///
  /// Intended for debugging and logging only; the result is not a safe way to
  /// execute a query. Use [toSql] and [getBindings] for execution.
  String toRawSql() {
    final compiled = _compileForDebug();
    return _grammar.numberedPlaceholders
        ? _interpolateNumberedBindings(compiled.sql, compiled.bindings)
        : _interpolateQuestionBindings(compiled.sql, compiled.bindings);
  }

  /// Dumps the compiled SQL and bindings to the console and returns [this]
  /// for continued chaining.
  QueryBuilder dump() {
    final compiled = _compileForDebug();
    // ignore: avoid_print
    print('SQL: ${compiled.sql}');
    // ignore: avoid_print
    print('Bindings: ${compiled.bindings}');
    return this;
  }

  /// Dumps the compiled SQL and bindings to the console and throws
  /// a [LaconicException] to halt execution.
  Never dd() {
    dump();
    throw LaconicException('QueryBuilder.dd() called — execution halted');
  }

  /// Prints the raw SQL with bindings substituted and returns [this].
  QueryBuilder dumpRawSql() {
    // ignore: avoid_print
    print('SQL: ${toRawSql()}');
    return this;
  }

  /// Prints the raw SQL with bindings substituted and halts execution.
  Never ddRawSql() {
    dumpRawSql();
    throw LaconicException('QueryBuilder.ddRawSql() called — execution halted');
  }

  static final RegExp _numberedPlaceholder = RegExp(r'\$(\d+)');

  String _interpolateNumberedBindings(String sql, List<Object?> bindings) {
    return sql.replaceAllMapped(_numberedPlaceholder, (match) {
      final index = int.parse(match[1]!) - 1;
      if (index < 0 || index >= bindings.length) {
        return match[0]!;
      }
      return _literal(bindings[index]);
    });
  }

  String _interpolateQuestionBindings(String sql, List<Object?> bindings) {
    final output = StringBuffer();
    var bindingIndex = 0;
    var i = 0;

    while (i < sql.length) {
      final code = sql.codeUnitAt(i);
      if (sql.startsWith('--', i)) {
        final end = sql.indexOf('\n', i + 2);
        final next = end == -1 ? sql.length : end;
        output.write(sql.substring(i, next));
        i = next;
        continue;
      }
      if (sql.startsWith('/*', i)) {
        final end = sql.indexOf('*/', i + 2);
        final next = end == -1 ? sql.length : end + 2;
        output.write(sql.substring(i, next));
        i = next;
        continue;
      }
      if (code == 39 || code == 34 || code == 96) {
        final quote = code;
        output.writeCharCode(quote);
        i++;
        while (i < sql.length) {
          final current = sql.codeUnitAt(i);
          output.writeCharCode(current);
          i++;
          if (current == quote) {
            if (i < sql.length && sql.codeUnitAt(i) == quote) {
              output.writeCharCode(quote);
              i++;
            } else {
              break;
            }
          }
        }
        continue;
      }
      if (code == 63) {
        if (bindingIndex < bindings.length) {
          output.write(_literal(bindings[bindingIndex++]));
        } else {
          output.write('?');
        }
        i++;
        continue;
      }
      output.writeCharCode(code);
      i++;
    }

    return output.toString();
  }

  static String _literal(Object? value) {
    if (value == null) return 'NULL';
    if (value is Expression) return value.sql;
    if (value is bool) return value ? '1' : '0';
    if (value is num || value is BigInt) return value.toString();
    if (value is DateTime) {
      final iso = value.toIso8601String();
      return "'${iso.substring(0, 19).replaceFirst('T', ' ')}'";
    }
    if (value is Uint8List) {
      final hex =
          value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      return "x'$hex'";
    }
    return "'${value.toString().replaceAll("'", "''")}'";
  }

  /// Compiles the current query state into a [CompiledQuery] for
  /// inspection via [toSql], [getBindings], or [dump].
  CompiledQuery _compileForDebug() => _compileSelect();

  CompiledQuery _compileGroupLimit({
    List<String>? columns,
    int? limitOverride,
  }) {
    final groupLimit = _groupLimit!;
    final groupValue = groupLimit['value'] as int;
    final groupColumn = groupLimit['column'] as String;

    final inner = clone();
    inner._groupLimit = null;
    inner._limit = null;
    inner._offset = null;
    inner._orders.clear();
    inner._locks.clear();

    final windowBindings = <Object?>[];
    final orderParts = <String>[];
    for (final order in _orders) {
      if (order['type'] == 'raw') {
        orderParts.add(order['sql'] as String);
        windowBindings.addAll(order['bindings'] as List<Object?>);
      } else {
        orderParts.add('${order['column']} ${order['direction']}');
      }
    }
    final orderSql =
        orderParts.isEmpty ? '' : ' order by ${orderParts.join(', ')}';
    final rowNumber =
        'row_number() over (partition by $groupColumn$orderSql) '
        'as laconic_row';

    if (columns != null) {
      inner._columns = List<String>.from(columns);
      inner._selectBindings.clear();
    }
    if (inner._columns.isEmpty) {
      inner._columns = ['*'];
    }
    inner._columns.add(rowNumber);
    inner._selectBindings.addAll(windowBindings);

    final innerCompiled = inner._compileSelect();
    final outerColumns =
        columns == null || columns.isEmpty ? '*' : columns.join(', ');
    final offset = _offset;

    final buffer = StringBuffer(
      'select $outerColumns from (${innerCompiled.sql}) as laconic_group '
      'where laconic_row <= $groupValue',
    );
    if (offset != null) {
      buffer.write(' and laconic_row > $offset');
    }
    buffer.write(' order by laconic_row');
    if (limitOverride != null) {
      buffer.write(' limit $limitOverride');
    }

    return CompiledQuery(
      sql: buffer.toString(),
      bindings: innerCompiled.bindings,
    );
  }

  CompiledQuery _compileSelect({
    List<String>? columns,
    int? limitOverride,
    List<Map<String, dynamic>> unionWheres = const [],
  }) {
    if (_groupLimit != null) {
      if (_unions.isNotEmpty || unionWheres.isNotEmpty) {
        throw LaconicException('groupLimit cannot be combined with UNION');
      }
      if (_distinct || _groups.isNotEmpty) {
        throw LaconicException(
          'groupLimit cannot be combined with distinct or group by',
        );
      }
      return _compileGroupLimit(columns: columns, limitOverride: limitOverride);
    }

    final hasUnion = _unions.isNotEmpty;
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: hasUnion ? _columns : columns ?? _columns,
      selectBindings:
          hasUnion
              ? _selectBindings
              : (columns == null ? _selectBindings : const []),
      wheres: _wheres,
      joins: _joins,
      orders: hasUnion ? [] : _orders,
      groups: _groups,
      groupBindings: _groupBindings,
      havings: _havings,
      distinct: _distinct,
      distinctColumns:
          hasUnion ? null : (_distinctOn ? (columns ?? _columns) : null),
      fromSubquery: _fromSubquery,
      fromAlias: _fromAlias,
      indexHints: _indexHints,
      limit: hasUnion ? null : limitOverride ?? _limit,
      offset: hasUnion ? null : _offset,
      locks: hasUnion ? [] : _locks,
    );
    if (!hasUnion) return compiled;
    return _grammar.compileUnion(
      queries: [
        compiled,
        for (final union in _unions)
          CompiledQuery(
            sql: union['sql'] as String,
            bindings: union['bindings'] as List<Object?>,
          ),
      ],
      all: [for (final union in _unions) union['all'] as bool],
      columns: columns ?? ['*'],
      wheres: unionWheres,
      orders: _orders,
      limit: limitOverride ?? _limit,
      offset: _offset,
      locks: _locks,
    );
  }
}
