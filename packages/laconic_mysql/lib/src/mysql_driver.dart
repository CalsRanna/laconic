import 'dart:async';

import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/src/client/mysql_client.dart';
import 'package:laconic_mysql/src/mysql_config.dart';
import 'package:laconic_mysql/src/mysql_grammar.dart';

/// MySQL driver implementation for Laconic.
///
/// This driver uses a lightweight connection pool that always returns
/// connections after use (including when queries throw). This avoids the
/// slot leak in the upstream client's connection pool.
///
/// The connection pool is lazily created on first use.
///
/// Uses MySQL prepared statements (binary protocol) via [MySQLConnection.prepare]
/// for parameterized queries. For queries without parameters (DDL like
/// CREATE DATABASE, etc.), uses the text protocol directly since MySQL's
/// COM_STMT_PREPARE does not support all statement types.
class MysqlDriver implements DatabaseDriver {
  final MysqlConfig config;
  MySQLConnectionPool? _pool;
  static final _grammar = MysqlGrammar();
  static final _txConnKey = Object();

  /// Cache of prepared statements keyed by connection hash + SQL.
  /// Avoids the PREPARE → DEALLOCATE round-trip per query.
  final Map<String, dynamic> _stmtCache = {};
  static const int _maxCachedStatements = 50;

  /// Creates a new MySQL driver with the given configuration.
  MysqlDriver(this.config);

  @override
  SqlGrammar get grammar => _grammar;

  MySQLConnectionPool get _connectionPool {
    return _pool ??= MySQLConnectionPool(
      databaseName: config.database,
      host: config.host,
      maxConnections: config.maxConnections,
      password: config.password,
      port: config.port,
      userName: config.username,
      onConnectionRemoved: _evictStatementsForConnection,
    );
  }

  /// Returns the pinned transaction connection from the current Zone, if any.
  MySQLConnection? get _transactionConnection =>
      Zone.current[_txConnKey] as MySQLConnection?;

  /// Executes a query, delegating to [_executeOnConn] for protocol selection.
  Future<IResultSet> _executeQuery(String sql, List<Object?> params) async {
    final conn = _transactionConnection;
    if (conn != null) {
      return _executeOnConn(conn, sql, params);
    }
    return _connectionPool.withConnection(
      (conn) => _executeOnConn(conn, sql, params),
    );
  }

  /// Executes a query on a given connection.
  ///
  /// When there are parameters, uses MySQL prepared statements (binary protocol)
  /// via [MySQLConnection.prepare] for safe parameter binding and efficient
  /// binary transfer. Prepared statements are cached to avoid the
  /// PREPARE → DEALLOCATE round-trip on repeated queries.
  ///
  /// When there are no parameters, uses the text protocol directly since
  /// MySQL's COM_STMT_PREPARE does not support all statement types (e.g., DDL).
  Future<IResultSet> _executeOnConn(
    MySQLConnection conn,
    String sql,
    List<Object?> params,
  ) async {
    if (params.isEmpty) {
      return conn.execute(sql);
    }

    final cacheKey = '${identityHashCode(conn)}:$sql';
    dynamic stmt = _stmtCache[cacheKey];
    if (stmt == null) {
      stmt = await conn.prepare(sql);
      // Evict oldest entry if cache is full
      if (_stmtCache.length >= _maxCachedStatements) {
        _stmtCache.remove(_stmtCache.keys.first);
      }
      _stmtCache[cacheKey] = stmt;
    }

    try {
      return await stmt.execute(params);
    } catch (e) {
      // Prepared statement may be stale (connection re-established).
      // Remove from cache and let the caller handle the error.
      _stmtCache.remove(cacheKey);
      rethrow;
    }
  }

  /// Drops all cached prepared statements for [conn].
  void _evictStatementsForConnection(MySQLConnection conn) {
    final prefix = '${identityHashCode(conn)}:';
    _stmtCache.removeWhere((key, _) => key.startsWith(prefix));
  }

  List<LaconicResult> _toResults(IResultSet results) {
    return results.rows.map((row) {
      final map = row.typedAssoc();
      return LaconicResult.fromMap(Map<String, Object?>.from(map));
    }).toList();
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final results = await _executeQuery(sql, params);
      return _toResults(results);
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    try {
      await _executeQuery(sql, params);
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
      final results = await _executeQuery(sql, params);
      return results.affectedRows.toInt();
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
      final results = await _executeQuery(sql, params);
      return results.lastInsertID.toInt();
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    try {
      return await _connectionPool.transactional((conn) async {
        return runZoned(() => action(), zoneValues: {_txConnKey: conn});
      });
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> close() async {
    _stmtCache.clear();
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
    }
  }
}
