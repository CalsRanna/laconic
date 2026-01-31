import 'package:laconic/src/database_driver.dart';
import 'package:laconic/src/query.dart';
import 'package:laconic/src/query_builder/grammar/grammar.dart';
import 'package:laconic/src/query_builder/query_builder.dart';
import 'package:laconic/src/result.dart';

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
/// final db = Laconic(SqliteDriver(SqliteConfig('app.db')));
/// final users = await db.table('users').where('active', true).get();
/// await db.close();
/// ```
class Laconic {
  final DatabaseDriver _driver;

  /// Optional listener for query execution.
  ///
  /// Called before each query is executed with query details.
  final void Function(LaconicQuery)? listen;

  /// Creates a new Laconic instance with the given driver.
  ///
  /// [driver] provides the database-specific implementation.
  /// [listen] is an optional callback for query logging/debugging.
  Laconic(this._driver, {this.listen});

  /// Returns the Grammar instance from the driver.
  ///
  /// The Grammar is responsible for compiling query components into
  /// database-specific SQL strings with parameter bindings.
  Grammar get grammar => _driver.grammar;

  /// Runs a SELECT statement against the database.
  ///
  /// [sql] is the SQL query string using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  ///
  /// Returns a list of [LaconicResult] objects representing the rows.
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    listen?.call(LaconicQuery(bindings: params, sql: sql));
    return _driver.select(sql, params);
  }

  /// Executes an SQL statement (INSERT/UPDATE/DELETE/DDL).
  ///
  /// [sql] is the SQL statement string using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    listen?.call(LaconicQuery(bindings: params, sql: sql));
    return _driver.statement(sql, params);
  }

  /// Executes an INSERT statement and returns the last inserted ID.
  ///
  /// [sql] is the SQL INSERT statement using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  ///
  /// For PostgreSQL, the SQL should include a RETURNING clause.
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    listen?.call(LaconicQuery(bindings: params, sql: sql));
    return _driver.insertAndGetId(sql, params);
  }

  /// Creates a query builder for the specified table.
  ///
  /// [table] is the table name, optionally with an alias (e.g., 'users u').
  ///
  /// Example:
  /// ```dart
  /// final users = await db.table('users').where('active', true).get();
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
  /// await db.transaction(() async {
  ///   await db.table('accounts').where('id', 1).decrement('balance', amount: 100);
  ///   await db.table('accounts').where('id', 2).increment('balance', amount: 100);
  /// });
  /// ```
  Future<T> transaction<T>(Future<T> Function() action) =>
      _driver.transaction(action);

  /// Closes the database connection and releases resources.
  ///
  /// Should be called when you're done using the database.
  Future<void> close() => _driver.close();
}
