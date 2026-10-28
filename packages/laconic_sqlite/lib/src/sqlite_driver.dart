import 'dart:async';

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
  final _transactionKey = Object();
  Future<void> _tail = Future.value();

  Future<T> _execute<T>(FutureOr<T> Function() action) async {
    try {
      final transaction = Zone.current[_transactionKey] as _SqliteTransaction?;
      if (transaction != null) {
        if (!transaction.active) {
          throw LaconicException('Transaction has already finished');
        }
        return await action();
      }
      final previous = _tail;
      final done = Completer<void>();
      _tail = done.future;
      await previous;
      try {
        return await action();
      } finally {
        done.complete();
      }
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw LaconicException(
        e.toString(),
        driver: driverName,
        code: _errorCode(e),
      );
    }
  }

  /// Cache of prepared statements keyed by SQL string.
  /// Avoids re-parsing SQL on every execution of the same query.
  final Map<String, PreparedStatement> _stmtCache = {};
  static const int _maxCachedStatements = 50;

  /// Creates a new SQLite driver with the given configuration.
  SqliteDriver(this.config);

  @override
  SqlGrammar get grammar => _grammar;

  /// Identifier reported on [LaconicException.driver].
  static const String driverName = 'sqlite';

  /// Extracts the SQLite extended result code for [LaconicException.code]
  /// (e.g. `2067` for UNIQUE, `1555` for FOREIGN KEY — see
  /// https://sqlite.org/rescode.html), or null for non-SQLite errors.
  static String? _errorCode(Object error) =>
      error is SqliteException ? '${error.extendedResultCode}' : null;

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
  ]) => _execute(() {
    try {
      final stmt = _prepare(sql);
      try {
        final rows = stmt.select(params);
        return LaconicResult.fromRows(
          rows.columnNames,
          rows.map((row) => row.values.toList()),
        );
      } catch (e) {
        // Schema may have changed; evict and let the caller handle the error.
        _stmtCache.remove(sql)?.close();
        rethrow;
      }
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw LaconicException(
        e.toString(),
        driver: driverName,
        code: _errorCode(e),
      );
    }
  });

  @override
  Stream<LaconicResult> selectStream(
    String sql, [
    List<Object?> params = const [],
  ]) async* {
    final transaction = Zone.current[_transactionKey] as _SqliteTransaction?;
    if (transaction != null) {
      if (!transaction.active) {
        throw LaconicException('Transaction has already finished');
      }
      yield* _streamRows(sql, params);
      return;
    }

    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      yield* _streamRows(sql, params);
    } finally {
      done.complete();
    }
  }

  Stream<LaconicResult> _streamRows(String sql, List<Object?> params) async* {
    try {
      final stmt = _prepare(sql);
      final rows = stmt.select(params);
      final columns = rows.columnNames;
      for (final row in rows) {
        yield LaconicResult.fromRows(columns, [row.values.toList()]).single;
      }
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw LaconicException(
        e.toString(),
        driver: driverName,
        code: _errorCode(e),
      );
    }
  }

  @override
  Future<void> statement(
    String sql, [
    List<Object?> params = const [],
  ]) => _execute(() {
    try {
      // SQLite creates sqlite_sequence only after the first AUTOINCREMENT
      // table exists. Truncate skips the sequence reset when it is absent.
      if (sql.startsWith('delete from sqlite_sequence ')) {
        final hasSequence =
            _db
                .select(
                  "select 1 from sqlite_master "
                  "where type = 'table' and name = 'sqlite_sequence' limit 1",
                )
                .isNotEmpty;
        if (!hasSequence) return;
      }

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
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw LaconicException(
        e.toString(),
        driver: driverName,
        code: _errorCode(e),
      );
    }
  });

  @override
  Future<int> affectingStatement(
    String sql, [
    List<Object?> params = const [],
  ]) => _execute(() {
    try {
      final stmt = _prepare(sql);
      try {
        stmt.execute(params);
        return _db.updatedRows;
      } catch (e) {
        _stmtCache.remove(sql)?.close();
        rethrow;
      }
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw LaconicException(
        e.toString(),
        driver: driverName,
        code: _errorCode(e),
      );
    }
  });

  @override
  Future<int> insertAndGetId(String sql, [List<Object?> params = const []]) =>
      _execute(() {
        try {
          final stmt = _prepare(sql);
          try {
            stmt.execute(params);
          } catch (e) {
            _stmtCache.remove(sql)?.close();
            rethrow;
          }
          return _db.lastInsertRowId;
        } catch (e) {
          if (e is LaconicException) rethrow;
          throw LaconicException(
            e.toString(),
            driver: driverName,
            code: _errorCode(e),
          );
        }
      });

  /// Closes and removes all cached prepared statements.
  void _invalidateCache() {
    for (final stmt in _stmtCache.values) {
      stmt.close();
    }
    _stmtCache.clear();
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) => _execute(() async {
    if (Zone.current[_transactionKey] != null) {
      throw LaconicException('Nested transactions are not supported');
    }
    final transaction = _SqliteTransaction();
    var started = false;
    try {
      _db.execute('BEGIN TRANSACTION');
      started = true;
      final result = await runZoned(
        action,
        zoneValues: {_transactionKey: transaction},
      );
      _db.execute('COMMIT');
      return result;
    } catch (e) {
      if (started) {
        try {
          _db.execute('ROLLBACK');
        } catch (rollbackError) {
          throw LaconicException(
            'Transaction failed: $e. Rollback also failed: $rollbackError',
            driver: driverName,
            code: _errorCode(e),
          );
        }
      }
      rethrow;
    } finally {
      transaction.active = false;
    }
  });

  @override
  Future<void> close() => _execute(() {
    if (Zone.current[_transactionKey] != null) {
      throw LaconicException(
        'Cannot close a connection inside its transaction',
      );
    }
    _invalidateCache();
    _database?.close();
    _database = null;
  });
}

class _SqliteTransaction {
  bool active = true;
}
