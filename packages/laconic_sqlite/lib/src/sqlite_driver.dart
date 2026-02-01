import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/src/sqlite_config.dart';
import 'package:laconic_sqlite/src/sqlite_grammar.dart';
import 'package:sqlite3/sqlite3.dart';

/// SQLite driver implementation for Laconic.
///
/// This driver uses the sqlite3 package for database operations.
/// The database connection is lazily opened on first use.
///
/// Example:
/// ```dart
/// final driver = SqliteDriver(SqliteConfig('app.db'));
/// final laconic = Laconic(driver);
/// ```
class SqliteDriver implements DatabaseDriver {
  final SqliteConfig config;
  Database? _database;
  static final _grammar = SqliteGrammar();

  /// Creates a new SQLite driver with the given configuration.
  SqliteDriver(this.config);

  @override
  SqlGrammar get grammar => _grammar;

  Database get _db {
    return _database ??= sqlite3.open(config.path);
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final stmt = _db.prepare(sql);
      final results = stmt.select(params);
      stmt.dispose();
      return results
          .map(
            (row) =>
                LaconicResult.fromMap(Map.fromIterables(row.keys, row.values)),
          )
          .toList();
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    try {
      final stmt = _db.prepare(sql);
      stmt.execute(params);
      stmt.dispose();
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final stmt = _db.prepare(sql);
      stmt.execute(params);
      stmt.dispose();
      // Get the last inserted row ID
      final result = _db.select('SELECT last_insert_rowid() as id');
      return result.first['id'] as int;
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    try {
      _db.execute('BEGIN TRANSACTION');
      final result = await action();
      _db.execute('COMMIT');
      return result;
    } catch (e, stackTrace) {
      try {
        _db.execute('ROLLBACK');
      } catch (rollbackError) {
        throw LaconicException(
          'Transaction failed: ${e.toString()}. '
          'Rollback also failed: ${rollbackError.toString()}',
          cause: e,
          stackTrace: stackTrace,
        );
      }
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> close() async {
    if (_database != null) {
      _database!.dispose();
      _database = null;
    }
  }
}
