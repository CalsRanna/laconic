import 'dart:async';
import 'dart:collection';

import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/src/client/connection/connection.dart';
import 'package:laconic_mysql/src/client/connection/connection_pool.dart';
import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/result/prepared_statement.dart';
import 'package:laconic_mysql/src/client/result/result_set.dart';
import 'package:laconic_mysql/src/mysql_config.dart';
import 'package:laconic_mysql/src/mysql_grammar.dart';

/// MySQL driver implementation for Laconic.
///
/// This driver uses a lightweight connection pool that always returns
/// connections after use (including when queries throw). This avoids the
/// connection-slot leaks when callbacks fail.
///
/// The connection pool is lazily created on first use.
///
/// Uses MySQL prepared statements (binary protocol) via [MysqlConnection.prepare]
/// for parameterized queries. For queries without parameters (DDL like
/// CREATE DATABASE, etc.), uses the text protocol directly since MySQL's
/// COM_STMT_PREPARE does not support all statement types.
class MysqlDriver implements DatabaseDriver {
  final MysqlConfig config;
  MysqlConnectionPool? _pool;
  static final _grammar = MysqlGrammar();
  static final _txConnKey = Object();

  /// Per-connection LRU caches of prepared statements.
  final Map<MysqlConnection, LinkedHashMap<String, MysqlPreparedStatement>>
  _stmtCache = {};
  static const int _maxCachedStatements = 50;

  /// Creates a new MySQL driver with the given configuration.
  MysqlDriver(this.config);

  @override
  SqlGrammar get grammar => _grammar;

  MysqlConnectionPool get _connectionPool {
    return _pool ??= MysqlConnectionPool(
      databaseName: config.database,
      host: config.host,
      maxConnections: config.maxConnections,
      password: config.password,
      port: config.port,
      userName: config.username,
      secure: config.useSsl,
      allowBadCertificates: config.allowBadCertificates,
      securityContext: config.securityContext,
      connectTimeout: config.connectTimeout,
      commandTimeout: config.commandTimeout,
      onConnectionRemoved: _evictStatementsForConnection,
    );
  }

  /// Returns the pinned transaction connection from the current Zone, if any.
  MysqlConnection? get _transactionConnection =>
      Zone.current[_txConnKey] as MysqlConnection?;

  /// Executes a query, delegating to [_executeOnConn] for protocol selection.
  Future<MysqlResultSet> _executeQuery(String sql, List<Object?> params) async {
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
  /// via [MysqlConnection.prepare] for safe parameter binding and efficient
  /// binary transfer. Prepared statements are cached to avoid the
  /// PREPARE → DEALLOCATE round-trip on repeated queries.
  ///
  /// When there are no parameters, uses the text protocol directly since
  /// MySQL's COM_STMT_PREPARE does not support all statement types (e.g., DDL).
  Future<MysqlResultSet> _executeOnConn(
    MysqlConnection conn,
    String sql,
    List<Object?> params,
  ) async {
    if (params.isEmpty) {
      return conn.execute(sql);
    }

    final connectionCache = _stmtCache.putIfAbsent(
      conn,
      LinkedHashMap<String, MysqlPreparedStatement>.new,
    );
    // Removing and reinserting makes the map insertion order an LRU order.
    var stmt = connectionCache.remove(sql);
    if (stmt == null) {
      stmt = await conn.prepare(sql);
      if (connectionCache.length >= _maxCachedStatements) {
        final oldestSql = connectionCache.keys.first;
        final oldest = connectionCache.remove(oldestSql)!;
        await oldest.deallocate();
      }
    }
    connectionCache[sql] = stmt;

    try {
      return await stmt.execute(params);
    } on MysqlServerException catch (error) {
      if (error.errorCode == 1243) {
        // ER_UNKNOWN_STMT_HANDLER: the server has already discarded it.
        connectionCache.remove(sql);
      }
      rethrow;
    }
  }

  /// Drops all cached prepared statements for [conn].
  void _evictStatementsForConnection(MysqlConnection conn) {
    _stmtCache.remove(conn);
  }

  List<LaconicResult> _toResults(MysqlResultSet results) {
    return results.rows.map((row) {
      final map = row.toTypedMap();
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
      return results.lastInsertId.toInt();
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
