import 'package:laconic/src/query_builder/grammar/grammar.dart';
import 'package:laconic/src/result.dart';

/// Abstract interface for database drivers.
///
/// Database drivers are responsible for executing SQL queries against
/// a specific database system. Each driver provides its own Grammar
/// implementation for generating database-specific SQL.
///
/// To create a custom driver, implement this interface and provide
/// the appropriate Grammar for your database system.
abstract class DatabaseDriver {
  /// Provides the SQL dialect Grammar instance for this driver.
  ///
  /// The Grammar is responsible for compiling query components into
  /// database-specific SQL strings with parameter bindings.
  Grammar get grammar;

  /// Executes a SELECT query and returns the result list.
  ///
  /// [sql] is the SQL query string using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  /// The driver is responsible for converting placeholders to the
  /// native format (e.g., `$1` for PostgreSQL, `:p0` for MySQL).
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]);

  /// Executes a non-query statement (INSERT/UPDATE/DELETE/DDL).
  ///
  /// [sql] is the SQL statement string using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  Future<void> statement(String sql, [List<Object?> params = const []]);

  /// Executes an INSERT statement and returns the auto-increment ID.
  ///
  /// [sql] is the SQL INSERT statement using `?` as placeholders.
  /// [params] are the parameter values to bind to the placeholders.
  ///
  /// For databases that require special syntax to retrieve the inserted ID
  /// (e.g., PostgreSQL RETURNING clause), the driver is responsible for
  /// handling this appropriately.
  Future<int> insertAndGetId(String sql, [List<Object?> params = const []]);

  /// Executes a callback within a database transaction.
  ///
  /// If the callback completes successfully, the transaction is committed.
  /// If an exception is thrown, the transaction is rolled back.
  Future<T> transaction<T>(Future<T> Function() action);

  /// Closes the database connection and releases resources.
  Future<void> close();
}
