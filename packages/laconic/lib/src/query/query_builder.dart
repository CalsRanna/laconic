import 'dart:async';

import '../database/result.dart';
import '../exception.dart';
import '../grammar/compiled_query.dart';
import '../grammar/expression.dart';
import '../grammar/grammar.dart';
import '../laconic.dart';
import 'join_clause.dart';
import 'operator.dart';
import 'pagination.dart';
import 'query_debug.dart';

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
  List<Object> _columns = ['*'];

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
  final List<Object> _groups = [];

  /// The HAVING conditions.
  final List<Map<String, dynamic>> _havings = [];

  /// Whether to select distinct records.
  bool _distinct = false;

  /// The columns used by PostgreSQL's `DISTINCT ON`.
  List<String>? _distinctColumns;

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

    if (_groups.isNotEmpty ||
        _unions.isNotEmpty ||
        (_distinct && isStar) ||
        _groupLimit != null) {
      final query = clone();
      if (_groupLimit == null) {
        query.reorder();
        query._offset = null;
      }
      query._limit = null;
      query._locks.clear();
      if (_unions.isEmpty &&
          _groups.isNotEmpty &&
          _columns.length == 1 &&
          _columns.first == '*') {
        // Group cardinality does not need the bound grouping expressions again.
        query._columns = [const Expression('1')];
        query._distinct = false;
        query._distinctColumns = null;
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
            ? 'COUNT(DISTINCT ${_grammar.wrap(column)}) as aggregate'
            : 'COUNT(${_grammar.wrap(column)}) as aggregate';
    final compiled = _grammar.compileSelect(
      table: _table,
      columns: [Expression(aggregate)],
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

    _validateWriteScope();
    final compiled = _grammar.compileDelete(
      table: _table,
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      limit: _limit,
      offset: _offset,
    );

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
  /// `insert into table (columns) <subquery>`, returning the affected row count.
  Future<int> insertUsing(List<String> columns, Object query) async {
    if (columns.isEmpty) {
      throw LaconicException('insertUsing requires at least one column');
    }
    final compiled = _compileSubquery(query);
    final sql =
        'insert into ${_grammar.wrapTable(_table)} (${columns.map(_grammar.wrap).join(', ')}) ${compiled.sql}';
    return _laconic.affectingStatement(sql, compiled.bindings);
  }

  /// Inserts rows produced by a subquery, ignoring duplicate-key errors.
  ///
  /// Returns the affected row count reported by the database.
  Future<int> insertOrIgnoreUsing(List<String> columns, Object query) async {
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
    return _laconic.affectingStatement(sql, compiled.bindings);
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
  /// Returns the affected row count reported by the database.
  Future<int> insertOrIgnore(List<Map<String, Object?>> data) async {
    if (data.isEmpty) {
      throw LaconicException('Cannot insert an empty list of data');
    }
    final compiled = _grammar.compileInsertOrIgnore(table: _table, data: data);
    return _laconic.affectingStatement(compiled.sql, compiled.bindings);
  }

  /// Performs an upsert: inserts new records or updates existing ones.
  ///
  /// [uniqueBy] lists the columns that determine uniqueness.
  /// If [update] is null, all non-unique columns are updated on conflict.
  /// Returns the database's affected row count, including its upsert-specific
  /// counting rules.
  Future<int> upsert(
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
    return _laconic.affectingStatement(compiled.sql, compiled.bindings);
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
      'table': '(${compiled.sql}) as ${_grammar.quoteSchemaIdentifier(as)}',
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
      'table': '(${compiled.sql}) as ${_grammar.quoteSchemaIdentifier(as)}',
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
      'table': '(${compiled.sql}) as ${_grammar.quoteSchemaIdentifier(as)}',
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
    if (limit < 0) throw LaconicException('Limit must be non-negative');
    _limit = limit;
    return this;
  }

  /// Sets the OFFSET for the query.
  QueryBuilder offset(int offset) {
    if (offset < 0) throw LaconicException('Offset must be non-negative');
    _offset = offset;
    return this;
  }

  /// Updates the row matching [attributes], or inserts a new row when none
  /// exists. [values] are applied on update and merged into the inserted row.
  /// [values] accepts a map or a synchronous/asynchronous callback receiving
  /// whether a matching row exists and returning a map.
  /// Returns whether an insert succeeds or an update affects a row; an empty
  /// update map returns `true` without issuing an update.
  Future<bool> updateOrInsert(
    Map<String, Object?> attributes, [
    Object values = const <String, Object?>{},
  ]) async {
    if (attributes.isEmpty) {
      throw LaconicException('updateOrInsert requires non-empty attributes');
    }

    final matches = clone();
    for (final entry in attributes.entries) {
      matches.where(entry.key, entry.value);
    }

    final exists = await matches.exists();
    final Map<String, Object?> data;
    if (values is Map<String, Object?>) {
      data = values;
    } else if (values is FutureOr<Map<String, Object?>> Function(bool)) {
      data = await values(exists);
    } else {
      throw LaconicException(
        'updateOrInsert expects a map or a values callback',
      );
    }
    if (!exists) {
      return insert([
        {...attributes, ...data},
      ]);
    }
    if (data.isEmpty) return true;
    return await matches.limit(1).update(data) > 0;
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
  /// [column] is a column name, a [QueryBuilder], or a synchronous callback
  /// building a scalar subquery. Subquery SQL and bindings are captured now.
  /// [direction] must be 'asc' or 'desc' (defaults to 'asc').
  QueryBuilder orderBy(Object column, {String direction = 'asc'}) {
    if (column is! String) {
      final normalized = direction.toLowerCase();
      if (normalized != 'asc' && normalized != 'desc') {
        throw LaconicException('Invalid ordering direction: $direction');
      }
      final compiled = _grammar.compileInlineSubquery(_compileSubquery(column));
      return orderByRaw('(${compiled.sql}) $normalized', compiled.bindings);
    }
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
  QueryBuilder orderByDesc(Object column) {
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
      'case ${_grammar.wrap(column)} ${clauses.join(' ')} else ${values.length} end',
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
  /// An [offset] skips rows within each partition, while [limit] caps the
  /// combined result. [paginate] and [simplePaginate] page the combined result
  /// after applying these per-partition constraints. [cursorPaginate] and
  /// [chunkById] also apply their cursors to that combined result, preserving
  /// the ordering and offset used to select rows within each partition.
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
    final query = _paginationQuery();
    final total = await query.clone().count();
    final lastPage = total == 0 ? 1 : (total + perPage - 1) ~/ perPage;
    final data = await query.forPage(page, perPage: perPage).get();
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
        await _paginationQuery()
            .limit(perPage + 1)
            .offset((page - 1) * perPage)
            .get();
    final hasMorePages = rows.length > perPage;
    final data = hasMorePages ? rows.sublist(0, perPage) : rows;
    return LaconicSimplePage(
      data: data,
      perPage: perPage,
      currentPage: page,
      hasMorePages: hasMorePages,
    );
  }

  /// Returns a page using the query's ORDER BY columns as a keyset.
  ///
  /// Ordering must be unique as a whole and all ordering values must be selected
  /// and non-null. Mixed ascending and descending columns are supported. Raw
  /// ordering is unsupported; select an expression with an alias and order by
  /// that alias instead. [column] supplies ascending ordering when no ORDER BY
  /// exists, and supplies the outer ordering for a group-limited query.
  ///
  /// Pass a page's next or previous [LaconicCursor] as [cursor] to move in either
  /// direction. A scalar cursor is also accepted for a single ordering column
  /// and moves forward. Returned rows always retain the query's ordering.
  Future<LaconicCursorPage> cursorPaginate(
    int perPage, {
    String column = 'id',
    Object? cursor,
  }) async {
    if (perPage < 1) {
      throw LaconicException('perPage must be greater than zero');
    }
    final orders =
        _groupLimit == null && _orders.isNotEmpty
            ? _orders.map((order) => Map<String, dynamic>.of(order)).toList()
            : <Map<String, dynamic>>[
              {'column': column, 'direction': 'asc'},
            ];
    for (final order in orders) {
      if (order['type'] == 'raw') {
        throw LaconicException(
          'cursorPaginate requires named ordering columns; select and order by an alias for expressions',
        );
      }
      final direction = (order['direction'] as String).toLowerCase();
      if (direction != 'asc' && direction != 'desc') {
        throw LaconicException('Invalid cursor ordering direction: $direction');
      }
      order['direction'] = direction;
    }
    final columns = [for (final order in orders) order['column'] as String];
    if (columns.toSet().length != columns.length) {
      throw LaconicException('Cursor ordering columns must be distinct');
    }
    final LaconicCursor? boundary;
    if (cursor == null || cursor is LaconicCursor) {
      boundary = cursor as LaconicCursor?;
    } else if (columns.length == 1) {
      boundary = LaconicCursor({columns.single: cursor});
    } else {
      throw LaconicException('Composite ordering requires a LaconicCursor');
    }
    if (boundary != null) {
      final parameters = boundary.parameters;
      if (parameters.length != columns.length ||
          columns.any((name) => parameters[name] == null)) {
        throw LaconicException(
          'Cursor values must match all ordering columns and be non-null',
        );
      }
    }
    final backwards = boundary != null && !boundary.pointsToNextItems;
    final resultColumns = [
      for (final name in columns) _cursorResultColumn(name),
    ];
    var q = _paginationQuery();
    var outer = _groupLimit != null || _unions.isNotEmpty;
    if (!outer &&
        (_groups.isNotEmpty ||
            _havings.isNotEmpty ||
            _distinct ||
            _columns.any(
              (selected) =>
                  selected is Expression ||
                  (selected is String &&
                      _grammar.wrap(selected).contains(' as ')),
            ))) {
      q.reorder();
      q._limit = null;
      q._offset = null;
      q = QueryBuilder(
        laconic: _laconic,
        table: _table,
      ).fromSub(q, 'laconic_cursor');
      outer = true;
    }
    q.reorder();
    q._offset = null;
    q._limit = perPage + 1;
    final predicateColumns = <String>[];
    for (var i = 0; i < orders.length; i++) {
      final name =
          outer ? _grammar.quoteSchemaIdentifier(resultColumns[i]) : columns[i];
      predicateColumns.add(name);
      final direction = orders[i]['direction'] as String;
      q.orderBy(
        name,
        direction:
            backwards ? (direction == 'asc' ? 'desc' : 'asc') : direction,
      );
    }
    final cursorWheres =
        boundary == null
            ? <Map<String, dynamic>>[]
            : _cursorWheres(orders, predicateColumns, boundary);
    if (cursorWheres.isNotEmpty && q._unions.isEmpty) {
      final conditions = List<Map<String, dynamic>>.of(q._wheres);
      q._wheres.clear();
      if (conditions.isNotEmpty) {
        q._wheres.add({
          'type': 'nested',
          'conditions': conditions,
          'boolean': 'and',
        });
      }
      q._wheres.addAll(cursorWheres);
    }
    final compiled = q._compileSelect(
      unionWheres: q._unions.isEmpty ? const [] : cursorWheres,
    );
    final rows = await _laconic.select(compiled.sql, compiled.bindings);
    final hasExtra = rows.length > perPage;
    var data = hasExtra ? rows.sublist(0, perPage) : rows;
    if (backwards) data = data.reversed.toList();

    Map<String, Object?> values(LaconicResult row) {
      final parameters = <String, Object?>{};
      for (var i = 0; i < columns.length; i++) {
        Object? value;
        try {
          value = row[resultColumns[i]];
        } on ArgumentError {
          throw LaconicException(
            'cursorPaginate requires selecting the ordering column "${columns[i]}"',
          );
        }
        if (value == null) {
          throw LaconicException('Cursor ordering values must be non-null');
        }
        parameters[columns[i]] = value;
      }
      return parameters;
    }

    final parameters = [for (final row in data) values(row)];
    final hasNext = data.isNotEmpty && (backwards || hasExtra);
    final hasPrevious =
        data.isNotEmpty && (backwards ? hasExtra : boundary != null);
    return LaconicCursorPage(
      data: data,
      perPage: perPage,
      nextCursor: hasNext ? LaconicCursor(parameters.last) : null,
      previousCursor:
          hasPrevious
              ? LaconicCursor(parameters.first, pointsToNextItems: false)
              : null,
      hasMorePages: hasNext,
    );
  }

  String _cursorResultColumn(String column) {
    final source = _grammar.wrap(column);
    for (final selected in _columns.whereType<String>()) {
      if (_grammar.wrap(selected).startsWith('$source as ')) {
        return _resultColumnName(selected);
      }
    }
    return _resultColumnName(column);
  }

  List<Map<String, dynamic>> _cursorWheres(
    List<Map<String, dynamic>> orders,
    List<String> columns,
    LaconicCursor cursor,
  ) {
    final alternatives = <Map<String, dynamic>>[];
    for (var i = 0; i < orders.length; i++) {
      final conditions = <Map<String, dynamic>>[];
      for (var j = 0; j <= i; j++) {
        final ascending = orders[j]['direction'] == 'asc';
        conditions.add({
          'type': 'basic',
          'column': columns[j],
          'comparator':
              j < i ? '=' : (ascending == cursor.pointsToNextItems ? '>' : '<'),
          'value': cursor.parameters[orders[j]['column']],
          'boolean': 'and',
        });
      }
      alternatives.add({
        'type': 'nested',
        'conditions': conditions,
        'boolean': 'or',
      });
    }
    return [
      {'type': 'nested', 'conditions': alternatives, 'boolean': 'and'},
    ];
  }

  /// Number of rows used by pagination.
  Future<int> getCountForPagination() => count();

  QueryBuilder _paginationQuery() {
    final query = clone();
    if (_groupLimit == null) return query;
    query._limit = null;
    return QueryBuilder(
      laconic: _laconic,
      table: _table,
    ).fromSub(query, 'laconic_group_page').orderBy('laconic_row');
  }

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
  /// [column] is a column name or a scalar subquery, as in [where].
  /// [value] is the value to compare.
  /// [comparator] is the comparison operator (defaults to '=').
  QueryBuilder orWhere(
    Object column,
    Object? value, {
    String comparator = '=',
  }) {
    final operator = SqlOperator.validate(comparator);

    if (column is! String) {
      return _whereSubquery(column, value, operator, 'or');
    }

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
  /// [query] accepts an existing [QueryBuilder] or a callback receiving a fresh
  /// builder. Use [from] to set the callback's table. SQL and bindings are
  /// captured now without modifying a supplied builder.
  ///
  /// Example:
  /// ```dart
  /// query.whereExists((q) =>
  ///   q.from('orders').whereColumn('orders.user_id', 'users.id'));
  /// ```
  QueryBuilder whereExists(Object query) {
    return _addExists(query, 'and', false);
  }

  /// Adds an OR WHERE EXISTS clause.
  QueryBuilder orWhereExists(Object query) {
    return _addExists(query, 'or', false);
  }

  /// Adds a WHERE NOT EXISTS clause.
  QueryBuilder whereNotExists(Object query) {
    return _addExists(query, 'and', true);
  }

  /// Adds an OR WHERE NOT EXISTS clause.
  QueryBuilder orWhereNotExists(Object query) {
    return _addExists(query, 'or', true);
  }

  QueryBuilder _addExists(Object query, String boolean, bool not) {
    final QueryBuilder subQuery;
    if (query is QueryBuilder) {
      subQuery = query;
    } else if (query is void Function(QueryBuilder)) {
      subQuery = QueryBuilder(laconic: _laconic, table: '');
      query(subQuery);
    } else {
      throw LaconicException('Expected a callback or QueryBuilder');
    }
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
      if (_groups.isNotEmpty || _havings.isEmpty) {
        query._columns = [const Expression('1')];
      }
    }
    return query._compileSelect();
  }

  Stream<List<LaconicResult>> _chunkStream(int count) async* {
    if (count <= 0) throw LaconicException('Chunk size must be positive');
    final base = _paginationQuery();
    if (base._orders.isEmpty) {
      throw LaconicException('chunk/lazy requires orderBy');
    }
    var offset = base._offset ?? 0;
    var remaining = _limit;
    while (remaining == null || remaining > 0) {
      final size = remaining == null || remaining > count ? count : remaining;
      final results = await base.clone().offset(offset).limit(size).get();
      if (results.isEmpty) break;
      final received = results.length;
      offset += received;
      if (remaining != null) remaining -= received;
      yield results;
      if (received < size) break;
    }
  }

  /// Processes bounded query results in chunks without mutating this builder.
  ///
  /// The callback accepts `(rows)` or `(rows, page)`, with one-based pages.
  /// It may be synchronous or asynchronous; returning `false` stops iteration.
  Future<bool> chunk(int count, Function callback) async {
    var page = 1;
    await for (final rows in _chunkStream(count)) {
      if (!await _callChunk(callback, rows, page++)) return false;
    }
    return true;
  }

  /// Collects mapped values while reading ordered query results in chunks.
  ///
  /// [callback] is awaited for each row in order. Null and false are collected
  /// as values; they do not stop iteration. The result list holds every mapped
  /// value, while source rows are fetched in batches of [count]. This builder's
  /// ordering, offset, limit and bindings are preserved.
  Future<List<T>> chunkMap<T>(
    FutureOr<T> Function(LaconicResult row) callback, {
    int count = 1000,
  }) async {
    final values = <T>[];
    await for (final rows in _chunkStream(count)) {
      for (final row in rows) {
        values.add(await callback(row));
      }
    }
    return values;
  }

  Future<bool> _callChunk(
    Function callback,
    List<LaconicResult> rows,
    int page,
  ) async {
    final arguments =
        callback is Function(List<LaconicResult>, int)
            ? <Object>[rows, page]
            : callback is Function(List<LaconicResult>)
            ? <Object>[rows]
            : throw LaconicException(
              'Chunk callback must accept rows and an optional page',
            );
    return await Function.apply(callback, arguments) != false;
  }

  /// Streams rows using ordered offset chunks, preserving OFFSET and LIMIT.
  Stream<LaconicResult> lazy([int count = 1000]) async* {
    await for (final rows in _chunkStream(count)) {
      yield* Stream.fromIterable(rows);
    }
  }

  /// Streams rows using the driver's native cursor when available.
  Stream<LaconicResult> cursor() {
    final compiled = _compileSelect();
    return _laconic.selectStream(compiled.sql, compiled.bindings);
  }

  Stream<List<LaconicResult>> _chunkByIdStream(
    int count, {
    String column = 'id',
    String? alias,
    bool descending = false,
  }) async* {
    if (count <= 0) throw LaconicException('Chunk size must be positive');
    final resultColumn = alias ?? _resultColumnName(column);
    final col = _groupLimit != null ? resultColumn : column;
    Object? lastId;
    var remaining = _limit;
    while (remaining == null || remaining > 0) {
      final size = remaining == null || remaining > count ? count : remaining;
      final q = _paginationQuery()..reorder();
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
        q.where(col, lastId, comparator: descending ? '<' : '>');
      }
      if (lastId != null) q._offset = null;
      q
          .orderBy(
            _unions.isEmpty ? col : resultColumn,
            direction: descending ? 'desc' : 'asc',
          )
          .limit(size);
      final compiled = q._compileSelect(
        unionWheres: [
          if (lastId != null && _unions.isNotEmpty)
            {
              'type': 'basic',
              'column': resultColumn,
              'comparator': descending ? '<' : '>',
              'value': lastId,
              'boolean': 'and',
            },
        ],
      );
      final results = await _laconic.select(compiled.sql, compiled.bindings);
      if (results.isEmpty) break;
      if (!results.last.columns.contains(resultColumn)) {
        throw LaconicException(
          'Chunk cursor column is missing from the result: $resultColumn',
        );
      }
      final nextId = results.last[resultColumn];
      if (nextId == null || nextId == lastId) {
        throw LaconicException('Chunk cursor must be non-null and advance');
      }
      lastId = nextId;
      final received = results.length;
      if (remaining != null) remaining -= received;
      yield results;
      if (received < size) break;
    }
  }

  /// Processes rows in ascending key order, preserving LIMIT and initial OFFSET.
  ///
  /// [column] is the SQL cursor column; [alias] is its name in the result row.
  /// The callback accepts `(rows)` or `(rows, page)` and may return `false`.
  Future<bool> chunkById(
    int count,
    Function callback, {
    String column = 'id',
    String? alias,
  }) => orderedChunkById(count, callback, column: column, alias: alias);

  /// Processes rows in descending key order, preserving LIMIT and initial OFFSET.
  ///
  /// [column] must be a unique, non-null key selected under [alias] when renamed.
  /// The callback receives `(rows)` or `(rows, page)` and may return `false`.
  /// Existing ordering is replaced without mutating this builder.
  Future<bool> chunkByIdDesc(
    int count,
    Function callback, {
    String column = 'id',
    String? alias,
  }) => orderedChunkById(
    count,
    callback,
    column: column,
    alias: alias,
    descending: true,
  );

  /// Processes rows in key order, optionally descending, without changing this query.
  ///
  /// [column] must be selected, unique and non-null; [alias] names it in results.
  /// Existing ordering is replaced, LIMIT is preserved and OFFSET applies only
  /// to the first chunk. With UNION or groupLimit, pages cover the complete result.
  /// [callback] accepts `(rows)` or `(rows, page)` with one-based pages, may be
  /// async, and stops iteration only when it returns `false`.
  Future<bool> orderedChunkById(
    int count,
    Function callback, {
    String column = 'id',
    String? alias,
    bool descending = false,
  }) async {
    var page = 1;
    await for (final rows in _chunkByIdStream(
      count,
      column: column,
      alias: alias,
      descending: descending,
    )) {
      if (!await _callChunk(callback, rows, page++)) return false;
    }
    return true;
  }

  /// Streams rows by a unique key; [alias] is the cursor's result-column name.
  Stream<LaconicResult> lazyById([
    int count = 1000,
    String column = 'id',
    String? alias,
  ]) async* {
    await for (final rows in _chunkByIdStream(
      count,
      column: column,
      alias: alias,
    )) {
      yield* Stream.fromIterable(rows);
    }
  }

  /// Streams rows in descending key order without changing this query.
  ///
  /// Uses the same unique-key, alias, LIMIT and initial OFFSET rules as
  /// [chunkByIdDesc]. Cancelling consumption stops further chunk queries.
  Stream<LaconicResult> lazyByIdDesc([
    int count = 1000,
    String column = 'id',
    String? alias,
  ]) async* {
    await for (final rows in _chunkByIdStream(
      count,
      column: column,
      alias: alias,
      descending: true,
    )) {
      yield* Stream.fromIterable(rows);
    }
  }

  Future<bool> _each(Stream<LaconicResult> rows, Function callback) async {
    var index = 0;
    await for (final row in rows) {
      final arguments =
          callback is Function(LaconicResult, int)
              ? <Object>[row, index]
              : callback is Function(LaconicResult)
              ? <Object>[row]
              : throw LaconicException(
                'Row callback must accept a row and an optional index',
              );
      if (await Function.apply(callback, arguments) == false) return false;
      index++;
    }
    return true;
  }

  /// Iterates by key; callbacks accept `(row)` or `(row, index)` (zero-based).
  Future<bool> eachById(
    Function callback, {
    int count = 1000,
    String column = 'id',
    String? alias,
  }) => _each(lazyById(count, column, alias), callback);

  /// Iterates ordered rows; returning `false` stops without fetching more chunks.
  Future<bool> each(Function callback, {int count = 1000}) =>
      _each(lazy(count), callback);

  /// Returns a deep copy of this QueryBuilder for reuse.
  QueryBuilder clone() {
    final copy =
        QueryBuilder(laconic: _laconic, table: _table)
          .._columns = List<Object>.from(_columns)
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
          .._distinctColumns =
              _distinctColumns == null
                  ? null
                  : List<String>.of(_distinctColumns!)
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
  QueryBuilder select(List<Object>? columns) {
    if (columns == null || columns.isEmpty) {
      _columns = ['*'];
    } else {
      _columns = List<Object>.of(columns);
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
  QueryBuilder addSelect(List<Object> columns) {
    if (_columns.contains('*')) {
      _columns = List<Object>.of(columns);
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
      _columns = [Expression(sql)];
      _selectBindings.clear();
    } else {
      _columns.add(Expression(sql));
    }
    _selectBindings.addAll(bindings);
    return this;
  }

  /// Adds a subquery to the SELECT clause as `(subquery) as as`.
  QueryBuilder selectSub(Object query, String as) {
    final compiled = _grammar.compileInlineSubquery(_compileSubquery(query));
    final sql = '(${compiled.sql}) as ${_grammar.quoteSchemaIdentifier(as)}';
    if (_columns.length == 1 && _columns[0] == '*') {
      _columns = [Expression(sql)];
      _selectBindings.clear();
    } else {
      _columns.add(Expression(sql));
    }
    _selectBindings.addAll(compiled.bindings);
    return this;
  }

  /// Passes this query to a synchronous callback and returns this builder.
  ///
  /// Changes made by [callback] remain on this query; its return value is ignored.
  /// Use [clone] first when the original query must remain unchanged.
  QueryBuilder tap(dynamic Function(QueryBuilder query) callback) {
    callback(this);
    return this;
  }

  /// Passes this query to a callback and returns its result.
  ///
  /// A synchronous null or void result returns this builder, matching Laravel.
  /// Other results, including futures, are returned unchanged. Use [tap] when
  /// composing synchronous query constraints without changing the return type.
  dynamic pipe(dynamic Function(QueryBuilder query) callback) =>
      callback(this) ?? this;

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
    final row = await clone().select([column]).sole();
    return row.values.first;
  }

  void _validateWriteScope() {
    if (_fromSubquery != null ||
        _groups.isNotEmpty ||
        _havings.isNotEmpty ||
        _unions.isNotEmpty ||
        _distinct ||
        _groupLimit != null ||
        _indexHints.isNotEmpty ||
        _locks.isNotEmpty) {
      throw LaconicException(
        'This query scope cannot be used for UPDATE or DELETE',
      );
    }
  }

  /// Updates records matching the query.
  ///
  /// [data] is a map of column-value pairs to update. Must be non-empty.
  /// Values may be scalar subqueries expressed as a [QueryBuilder] or a
  /// synchronous callback, compiled with their bindings before execution.
  /// Returns the number of affected rows reported by the database.
  Future<int> update(Map<String, Object?> data) async {
    if (data.isEmpty) {
      throw LaconicException('Cannot update with an empty data map');
    }
    _validateWriteScope();
    final compiled = _grammar.compileUpdate(
      table: _table,
      data: _compileUpdateValues(data),
      wheres: _wheres,
      joins: _joins,
      orders: _orders,
      limit: _limit,
      offset: _offset,
    );

    return _laconic.affectingStatement(compiled.sql, compiled.bindings);
  }

  /// Adds a WHERE condition to the query.
  ///
  /// [column] is a column name, a [QueryBuilder], or a synchronous callback
  /// building a scalar subquery. [value] may also be a scalar subquery.
  /// Subquery SQL and bindings are captured when the condition is added.
  /// [comparator] is the comparison operator (defaults to '=').
  QueryBuilder where(Object column, Object? value, {String comparator = '='}) {
    final operator = SqlOperator.validate(comparator);

    if (column is! String) {
      return _whereSubquery(column, value, operator, 'and');
    }

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

  QueryBuilder _whereSubquery(
    Object query,
    Object? value,
    String operator,
    String boolean,
  ) {
    final left = _grammar.compileInlineSubquery(_compileSubquery(query));
    final bindings = List<Object?>.of(left.bindings);
    final String sql;
    if (value == null &&
        (operator == '=' || operator == '!=' || operator == '<>')) {
      sql = '(${left.sql}) is ${operator == '=' ? '' : 'not '}null';
    } else {
      final String right;
      if (value is QueryBuilder || value is void Function(QueryBuilder)) {
        final compiled = _grammar.compileInlineSubquery(
          _compileSubquery(value as Object),
        );
        right = '(${compiled.sql})';
        bindings.addAll(compiled.bindings);
      } else if (value is Expression) {
        right = value.sql;
      } else {
        right = '?';
        bindings.add(value);
      }
      sql = '(${left.sql}) $operator $right';
    }
    return boolean == 'and'
        ? whereRaw(sql, bindings)
        : orWhereRaw(sql, bindings);
  }

  Map<String, Object?> _compileUpdateValues(Map<String, Object?> data) => {
    for (final entry in data.entries)
      entry.key:
          entry.value is QueryBuilder ||
                  entry.value is void Function(QueryBuilder)
              ? _compileSubquery(entry.value as Object)
              : entry.value,
  };

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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'operator': SqlOperator.validate(operator),
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
      'operator': SqlOperator.validate(operator),
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
      'comparator': SqlOperator.validate(comparator),
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
  /// SQLite searches the specified columns of an FTS5 virtual table.
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

  String _normalizeJsonPath(String path) => _grammar.jsonPath(path.trim());

  ({String column, String? path}) _splitJsonColumn(String column) {
    if (!column.contains('->')) {
      return (column: column.trim(), path: null);
    }
    final selector = _grammar.splitJsonSelector(column);
    return (
      column: selector.column.trim(),
      path: _normalizeJsonPath(selector.path),
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

  /// Adds AND conditions for dates before now.
  ///
  /// [columns] is a column name or a list of names. Each condition uses AND;
  /// the OR variants use OR per column. Use [whereNested] for explicit grouping.
  /// [now] defaults to the application clock, captured once when called. Its
  /// calendar fields are bound as `yyyy-MM-dd HH:mm:ss` at second precision,
  /// without timezone conversion; use a clock matching the stored values.
  /// Null database values do not match. This is not the database server's clock.
  QueryBuilder wherePast(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '<', 'and', dateOnly: false, now: now);

  /// Adds OR conditions for dates before now.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  QueryBuilder orWherePast(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '<', 'or', dateOnly: false, now: now);

  /// Adds AND conditions for dates at or before now.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  QueryBuilder whereNowOrPast(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '<=', 'and', dateOnly: false, now: now);

  /// Adds OR conditions for dates at or before now.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  QueryBuilder orWhereNowOrPast(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '<=', 'or', dateOnly: false, now: now);

  /// Adds AND conditions for dates after now.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  QueryBuilder whereFuture(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '>', 'and', dateOnly: false, now: now);

  /// Adds OR conditions for dates after now.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  QueryBuilder orWhereFuture(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '>', 'or', dateOnly: false, now: now);

  /// Adds AND conditions for dates at or after now.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  QueryBuilder whereNowOrFuture(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '>=', 'and', dateOnly: false, now: now);

  /// Adds OR conditions for dates at or after now.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  QueryBuilder orWhereNowOrFuture(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '>=', 'or', dateOnly: false, now: now);

  /// Adds AND conditions for dates today.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder whereToday(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '=', 'and', dateOnly: true, now: now);

  /// Adds OR conditions for dates today.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder orWhereToday(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '=', 'or', dateOnly: true, now: now);

  /// Adds AND conditions for dates before today.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder whereBeforeToday(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '<', 'and', dateOnly: true, now: now);

  /// Adds OR conditions for dates before today.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder orWhereBeforeToday(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '<', 'or', dateOnly: true, now: now);

  /// Adds AND conditions for dates today or earlier.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder whereTodayOrBefore(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '<=', 'and', dateOnly: true, now: now);

  /// Adds OR conditions for dates today or earlier.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder orWhereTodayOrBefore(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '<=', 'or', dateOnly: true, now: now);

  /// Adds AND conditions for dates after today.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder whereAfterToday(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '>', 'and', dateOnly: true, now: now);

  /// Adds OR conditions for dates after today.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder orWhereAfterToday(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '>', 'or', dateOnly: true, now: now);

  /// Adds AND conditions for dates today or later.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder whereTodayOrAfter(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '>=', 'and', dateOnly: true, now: now);

  /// Adds OR conditions for dates today or later.
  ///
  /// Accepts one column or a list; see [wherePast] for clock and grouping rules.
  /// Compares date parts with the calendar date of [now], ignoring the time.
  QueryBuilder orWhereTodayOrAfter(Object columns, {DateTime? now}) =>
      _whereRelativeDate(columns, '>=', 'or', dateOnly: true, now: now);

  QueryBuilder _whereRelativeDate(
    Object columns,
    String comparator,
    String boolean, {
    required bool dateOnly,
    DateTime? now,
  }) {
    final List<String> names;
    if (columns is String) {
      names = [columns];
    } else if (columns is List && columns.every((column) => column is String)) {
      names = columns.cast<String>();
    } else {
      throw LaconicException(
        'Expected a column name or a list of column names',
      );
    }
    final reference = now ?? DateTime.now();
    String pad(int value, [int width = 2]) => '$value'.padLeft(width, '0');
    final date =
        '${pad(reference.year, 4)}-${pad(reference.month)}-${pad(reference.day)}';
    final value =
        dateOnly
            ? date
            : '$date ${pad(reference.hour)}:${pad(reference.minute)}:${pad(reference.second)}';
    for (final column in names) {
      _wheres.add({
        'type': dateOnly ? 'date' : 'basic',
        if (dateOnly) 'dateType': 'date',
        'column': column,
        'comparator': comparator,
        'value': value,
        'boolean': boolean,
      });
    }
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
      'comparator': SqlOperator.validate(comparator),
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
    _groups.add(Expression(sql));
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
  QueryBuilder having(Object column, Object? value, {String comparator = '='}) {
    _havings.add({
      'column': column,
      'comparator': SqlOperator.validate(comparator),
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
    Object column,
    Object? value, {
    String comparator = '=',
  }) {
    _havings.add({
      'column': column,
      'comparator': SqlOperator.validate(comparator),
      'value': value,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a HAVING ... BETWEEN condition.
  QueryBuilder havingBetween(
    Object column, {
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
    Object column, {
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
    Object column, {
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
    Object column, {
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
  QueryBuilder havingNull(Object column) {
    _havings.add({
      'type': 'null',
      'column': column,
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds an OR HAVING ... IS NULL condition.
  QueryBuilder orHavingNull(Object column) {
    _havings.add({
      'type': 'null',
      'column': column,
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds a HAVING ... IS NOT NULL condition.
  QueryBuilder havingNotNull(Object column) {
    _havings.add({
      'type': 'null',
      'column': column,
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds an OR HAVING ... IS NOT NULL condition.
  QueryBuilder orHavingNotNull(Object column) {
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
  /// Subsequent projection changes retain PostgreSQL's original distinct keys.
  QueryBuilder distinct([List<String>? columns]) {
    _distinct = true;
    if (columns != null && columns.isNotEmpty) {
      _columns = List<Object>.of(columns);
      _selectBindings.clear();
      _distinctColumns = List<String>.of(columns);
    } else {
      _distinctColumns = null;
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
    return _numericAggregateValue(value)?.toDouble();
  }

  /// Returns the sum of a column's values.
  ///
  /// [column] is the column name to sum.
  ///
  /// Example:
  /// ```dart
  /// final totalVotes = await query.sum('votes');
  /// ```
  /// Returns zero when no non-null values match.
  Future<num> sum(String column) async {
    return _numericAggregateValue(await _aggregate('SUM', column)) ?? 0;
  }

  /// Returns the maximum value of a column.
  ///
  /// [column] is the column name.
  ///
  /// Example:
  /// ```dart
  /// final maxPrice = await query.max('price');
  /// ```
  /// Preserves the driver's value type, including strings and dates.
  /// Returns `null` when no non-null values match.
  Future<Object?> max(String column) async {
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
  /// Preserves the driver's value type, including strings and dates.
  /// Returns `null` when no non-null values match.
  Future<Object?> min(String column) async {
    return _aggregate('MIN', column);
  }

  /// Helper method for aggregate functions.
  ///
  /// Preserves all query clauses. When GROUP BY is present, returns the
  /// aggregate value from the first group only. For grouped aggregates
  /// that require all group values, use [get] with [selectRaw] instead.
  Future<Object?> _aggregate(String function, String column) async {
    if (_unions.isNotEmpty) {
      final query = clone()..reorder();
      query._limit = null;
      query._offset = null;
      query._locks.clear();
      final inner = query._compileSelect();
      final results = await _laconic.select(
        'select ${_grammar.compileAggregateExpression(function, column)} as aggregate from (${inner.sql}) as laconic_aggregate',
        inner.bindings,
      );
      return results.isEmpty ? null : results.first['aggregate'];
    }

    final compiled = _grammar.compileSelect(
      table: _table,
      columns: [
        Expression(
          '${_grammar.compileAggregateExpression(function, column, distinct: _distinct)} as aggregate',
        ),
      ],
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
      limit: _groups.isEmpty ? null : 1,
      offset: null,
      locks: const [],
    );

    final results = await _laconic.select(compiled.sql, compiled.bindings);

    return results.isEmpty ? null : results.first['aggregate'];
  }

  num? _numericAggregateValue(Object? value) =>
      value is num
          ? value
          : value is String
          ? num.tryParse(value)
          : null;

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

  /// Returns `true` when rows exist, otherwise executes [callback].
  Future<Object?> existsOr(FutureOr<Object?> Function() callback) async {
    return await exists() ? true : await callback();
  }

  /// Returns `true` when no rows exist, otherwise executes [callback].
  Future<Object?> doesntExistOr(FutureOr<Object?> Function() callback) async {
    return await doesntExist() ? true : await callback();
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
        map[row.values.first] = row.values.last;
      }
      return map;
    } else {
      // Return as List
      return results.map((row) => row.values.first).toList();
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

    return results.first.values.first;
  }

  /// Retrieves the first value of a bound SQL expression without changing this query.
  ///
  /// Replaces the selected columns for this read and returns null for no rows or
  /// SQL NULL. [expression] is trusted SQL; pass values through [bindings]. For
  /// UNION and groupLimit, the expression references columns exposed by the
  /// complete result. Existing ordering and offset still select the first row.
  Future<Object?> rawValue(
    String expression, [
    List<Object?> bindings = const [],
  ]) async {
    final QueryBuilder query;
    if (_unions.isNotEmpty) {
      final source =
          clone()
            ..reorder()
            .._limit = null
            .._offset = null
            .._locks.clear();
      query =
          QueryBuilder(
              laconic: _laconic,
              table: _table,
            ).fromSub(source, 'laconic_value')
            .._orders.addAll(_orders)
            .._offset = _offset
            .._locks.addAll(_locks);
    } else {
      query = _paginationQuery();
    }
    final row =
        await query.select([]).selectRaw(expression, bindings).firstOrNull();
    return row?.values.first;
  }

  String _resultColumnName(String column) => _grammar.resultColumnName(column);

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

    return _adjustEach('+', {column: amount}, extra, allowWithoutWhere);
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

    return _adjustEach('-', {column: amount}, extra, allowWithoutWhere);
  }

  /// Updates rows using a `FROM` clause. PostgreSQL only.
  Future<int> updateFrom(String from, Map<String, Object?> data) async {
    if (data.isEmpty) {
      throw LaconicException('Cannot update with an empty data map');
    }
    _validateWriteScope();
    if (_joins.isNotEmpty ||
        _orders.isNotEmpty ||
        _limit != null ||
        _offset != null) {
      throw LaconicException(
        'updateFrom does not support JOIN, ORDER BY, LIMIT or OFFSET',
      );
    }
    final compiled = _grammar.compileUpdateFrom(
      table: _table,
      from: from,
      data: _compileUpdateValues(data),
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
        entry.key: Expression(
          '${_grammar.wrap(entry.key)} $operator ${entry.value}',
        ),
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
    return QueryDebug.interpolate(
      _compileForDebug(),
      numberedPlaceholders: _grammar.numberedPlaceholders,
    );
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

  /// Compiles the current query state into a [CompiledQuery] for
  /// inspection via [toSql], [getBindings], or [dump].
  CompiledQuery _compileForDebug() => _compileSelect();

  CompiledQuery _compileGroupLimit({
    List<Object>? columns,
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
        orderParts.add(
          '${_grammar.wrap(order['column'] as String)} ${order['direction']}',
        );
      }
    }
    final orderSql =
        ' order by ${orderParts.isEmpty ? _grammar.wrap(groupColumn) : orderParts.join(', ')}';
    final rowNumber =
        'row_number() over (partition by ${_grammar.wrap(groupColumn)}$orderSql) '
        'as laconic_row';

    if (columns != null) {
      inner._columns = List<Object>.from(columns);
      inner._selectBindings.clear();
    }
    if (inner._columns.isEmpty) {
      inner._columns = ['*'];
    }
    inner._columns.add(Expression(rowNumber));
    inner._selectBindings.addAll(windowBindings);

    final innerCompiled = inner._compileSelect();
    final offset = _offset;
    return _grammar.compileSelect(
      table: 'laconic_group',
      columns: columns == null || columns.isEmpty ? ['*'] : columns,
      fromSubquery: innerCompiled,
      fromAlias: 'laconic_group',
      wheres: [
        {
          'type': 'basic',
          'column': 'laconic_row',
          'comparator': '<=',
          'value': groupValue,
          'boolean': 'and',
        },
        if (offset != null)
          {
            'type': 'basic',
            'column': 'laconic_row',
            'comparator': '>',
            'value': offset,
            'boolean': 'and',
          },
      ],
      joins: [],
      orders: [
        {'column': 'laconic_row', 'direction': 'asc'},
      ],
      groups: [],
      havings: [],
      distinct: false,
      limit: limitOverride ?? _limit,
    );
  }

  CompiledQuery _compileSelect({
    List<Object>? columns,
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
      distinctColumns: hasUnion ? null : _distinctColumns,
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
