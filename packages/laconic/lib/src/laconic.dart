import 'database/database_driver.dart';
import 'database/query.dart';
import 'database/result.dart';
import 'grammar/grammar.dart';
import 'query/query_builder.dart';
import 'schema/schema_builder.dart';

/// The main entry point for building and executing database queries.
///
/// Laconic uses a driver-based architecture where the database-specific
/// implementation is provided through a [DatabaseDriver] instance.
///
/// Example usage:
/// ```dart
/// import 'package:laconic/laconic.dart';
/// import 'package:laconic_sqlite/laconic_sqlite.dart';
///
/// final laconic = Laconic(SqliteDriver(SqliteConfig('app.db')));
/// final users = await laconic.table('users').where('active', true).get();
/// await laconic.close();
/// ```
class Laconic {
  final DatabaseDriver _driver;

  /// Optional listener for query execution.
  ///
  /// Called before each query is executed with query details. Kept for
  /// backwards compatibility; prefer [beforeQuery].
  final void Function(LaconicQuery)? listen;

  /// Called before each query is executed.
  final void Function(LaconicQuery)? beforeQuery;

  /// Called after each query completes, with its elapsed time.
  final void Function(LaconicQuery query, Duration elapsed)? afterQuery;

  /// Creates a new Laconic instance with the given driver.
  ///
  /// [driver] provides the database-specific implementation.
  /// [listen] is a legacy callback for query logging/debugging.
  /// [beforeQuery] and [afterQuery] wrap each query with timing support.
  Laconic(this._driver, {this.listen, this.beforeQuery, this.afterQuery});

  Future<T> _executeQuery<T>(
    LaconicQuery query,
    Future<T> Function() action,
  ) async {
    beforeQuery?.call(query);
    listen?.call(query);

    final stopwatch = Stopwatch()..start();
    try {
      return await action();
    } finally {
      stopwatch.stop();
      afterQuery?.call(query, stopwatch.elapsed);
    }
  }

  /// Returns the SqlGrammar instance from the driver.
  ///
  /// The SqlGrammar is responsible for compiling query components into
  /// database-specific SQL strings with parameter bindings.
  SqlGrammar get grammar => _driver.grammar;

  /// The table structure builder using this connection and its SQL grammar.
  late final SchemaBuilder schema = SchemaBuilder(this);

  /// Runs a SELECT statement against the database.
  ///
  /// [sql] is the SQL query string using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  ///
  /// Returns a list of [LaconicResult] objects representing the rows.
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final query = LaconicQuery(bindings: params, sql: sql);
    return _executeQuery(query, () => _driver.select(sql, params));
  }

  /// Runs a SELECT statement and streams its rows.
  Stream<LaconicResult> selectStream(
    String sql, [
    List<Object?> params = const [],
  ]) async* {
    final query = LaconicQuery(bindings: params, sql: sql);
    beforeQuery?.call(query);
    listen?.call(query);

    final stopwatch = Stopwatch()..start();
    try {
      yield* _driver.selectStream(sql, params);
    } finally {
      stopwatch.stop();
      afterQuery?.call(query, stopwatch.elapsed);
    }
  }

  /// Executes an SQL statement (INSERT/UPDATE/DELETE/DDL).
  ///
  /// [sql] is the SQL statement string using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  Future<void> statement(String sql, [List<Object?> params = const []]) {
    final query = LaconicQuery(bindings: params, sql: sql);
    return _executeQuery(query, () => _driver.statement(sql, params));
  }

  /// Executes an UPDATE/DELETE statement and returns the affected row count.
  ///
  /// [sql] is the SQL statement string using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  Future<int> affectingStatement(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final query = LaconicQuery(bindings: params, sql: sql);
    return _executeQuery(query, () => _driver.affectingStatement(sql, params));
  }

  /// Executes an INSERT statement and returns the last inserted ID.
  ///
  /// [sql] is the SQL INSERT statement using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  ///
  /// For PostgreSQL, the SQL should include a RETURNING clause.
  Future<int> insertAndGetId(String sql, [List<Object?> params = const []]) {
    final query = LaconicQuery(bindings: params, sql: sql);
    return _executeQuery(query, () => _driver.insertAndGetId(sql, params));
  }

  /// Creates a query builder for the specified table.
  ///
  /// [table] is the table name, optionally with an alias (e.g., 'users u').
  ///
  /// Example:
  /// ```dart
  /// final users = await laconic.table('users').where('active', true).get();
  /// ```
  QueryBuilder table(String table) {
    return QueryBuilder(laconic: this, table: table);
  }

  /// Executes a callback within a database transaction.
  ///
  /// If the callback completes successfully, the transaction is committed.
  /// If an exception is thrown, the transaction is rolled back.
  ///
  /// Example:
  /// ```dart
  /// await laconic.transaction(() async {
  ///   await laconic.table('accounts').where('id', 1).decrement('balance', amount: 100);
  ///   await laconic.table('accounts').where('id', 2).increment('balance', amount: 100);
  /// });
  /// ```
  Future<T> transaction<T>(Future<T> Function() action) =>
      _driver.transaction(action);

  /// Closes the database connection and releases resources.
  ///
  /// Should be called when you're done using the database.
  Future<void> close() => _driver.close();
}
