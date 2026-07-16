import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/src/sqlite_config.dart';
import 'package:laconic_sqlite/src/sqlite_grammar.dart';
import 'package:sqlite3/sqlite3.dart';

/// SQLite driver implementation for Laconic.
///
/// This driver uses the sqlite3 package for database operations.
/// The database connection is lazily opened on first use.
///
/// Prepared statements are cached (up to 50) to avoid the
/// parse → codegen → finalize cycle on repeated queries.
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

  /// Cache of prepared statements keyed by SQL string.
  /// Avoids re-parsing SQL on every execution of the same query.
  final Map<String, PreparedStatement> _stmtCache = {};
  static const int _maxCachedStatements = 50;

  /// Creates a new SQLite driver with the given configuration.
  SqliteDriver(this.config);

  @override
  SqlGrammar get grammar => _grammar;

  Database get _db {
    return _database ??= sqlite3.open(config.path);
  }

  /// Returns a cached or newly-prepared statement for [sql].
  ///
  /// DDL statements (CREATE, DROP, ALTER) are never cached because
  /// they are typically executed once and would invalidate other cached
  /// statements when the schema changes.
  PreparedStatement _prepare(String sql) {
    final stmt = _stmtCache[sql];
    if (stmt != null) return stmt;

    final newStmt = _db.prepare(sql);
    if (_stmtCache.length >= _maxCachedStatements) {
      // Evict the oldest entry (Map preserves insertion order)
      final oldestKey = _stmtCache.keys.first;
      _stmtCache[oldestKey]!.close();
      _stmtCache.remove(oldestKey);
    }
    _stmtCache[sql] = newStmt;
    return newStmt;
  }

  /// Whether [sql] is a DDL statement that changes the schema.
  bool _isDDL(String sql) {
    final upper = sql.trimLeft().toUpperCase();
    return upper.startsWith('CREATE') ||
        upper.startsWith('DROP') ||
        upper.startsWith('ALTER');
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final stmt = _prepare(sql);
      try {
        final rows = stmt.select(params);
        return rows
            .map((row) => LaconicResult.fromMap(
                Map.fromIterables(row.keys, row.values)))
            .toList();
      } catch (e) {
        // Schema may have changed; evict and let the caller handle the error.
        _stmtCache.remove(sql)?.close();
        rethrow;
      }
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    try {
      // DDL is not cached — it runs once and may invalidate other statements.
      if (_isDDL(sql)) {
        _invalidateCache();
        final stmt = _db.prepare(sql);
        try {
          stmt.execute(params);
        } finally {
          stmt.close();
        }
        return;
      }

      final stmt = _prepare(sql);
      try {
        stmt.execute(params);
      } catch (e) {
        _stmtCache.remove(sql)?.close();
        rethrow;
      }
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<int> affectingStatement(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final stmt = _prepare(sql);
      try {
        stmt.execute(params);
        return _db.updatedRows;
      } catch (e) {
        _stmtCache.remove(sql)?.close();
        rethrow;
      }
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
      final stmt = _prepare(sql);
      try {
        stmt.execute(params);
      } catch (e) {
        _stmtCache.remove(sql)?.close();
        rethrow;
      }
      // Get the last inserted row ID
      final result = _db.select('SELECT last_insert_rowid() as id');
      if (result.isEmpty) {
        throw LaconicException('Failed to retrieve last insert ID');
      }
      final id = result.first['id'];
      if (id is! int) {
        throw LaconicException('last_insert_rowid() returned non-integer: $id');
      }
      return id;
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  /// Closes and removes all cached prepared statements.
  void _invalidateCache() {
    for (final stmt in _stmtCache.values) {
      stmt.close();
    }
    _stmtCache.clear();
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
    _invalidateCache();
    if (_database != null) {
      _database!.close();
      _database = null;
    }
  }
}
