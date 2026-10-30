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
class MysqlDriver
    implements DatabaseDriver, MigrationLockDriver, SchemaStateDriver {
  final MysqlConfig config;
  MysqlConnectionPool? _pool;
  static final _grammar = MysqlGrammar();
  final _txConnKey = Object();
  final _migrationConnKey = Object();

  _MysqlTransaction? get _migrationContext =>
      Zone.current[_migrationConnKey] as _MysqlTransaction?;

  /// Per-connection LRU caches of prepared statements.
  final Map<MysqlConnection, LinkedHashMap<String, MysqlPreparedStatement>>
  _stmtCache = {};
  static const int _maxCachedStatements = 50;

  /// Creates a new MySQL driver with the given configuration.
  MysqlDriver(this.config);

  @override
  String get schemaDialect => 'mysql';

  /// Native client used to export schema definitions.
  String get schemaDumpExecutable => 'mysqldump';

  /// Native client used to load schema definitions.
  String get schemaLoadExecutable => 'mysql';

  List<String> _schemaArguments() {
    if (config.securityContext != null || config.serverPublicKey != null) {
      throw LaconicException(
        'Native schema clients cannot reuse a Dart SecurityContext or in-memory pinned RSA key',
      );
    }
    return [
      '--no-defaults',
      '--host=${config.host}',
      '--port=${config.port}',
      '--user=${config.username}',
      '--protocol=TCP',
      '--default-character-set=utf8mb4',
      if (schemaDialect == 'mysql')
        config.allowPublicKeyRetrieval
            ? '--get-server-public-key'
            : '--skip-get-server-public-key',
      if (schemaDialect == 'mariadb') ...[
        config.useSsl ? '--ssl' : '--skip-ssl',
        if (config.useSsl && !config.allowBadCertificates)
          '--ssl-verify-server-cert',
      ] else
        '--ssl-mode=${config.useSsl ? (config.allowBadCertificates ? 'REQUIRED' : 'VERIFY_IDENTITY') : 'DISABLED'}',
    ];
  }

  @override
  Future<void> dumpSchema(
    String path, {
    String? schema,
    SchemaProcessRunner? runner,
  }) async {
    try {
      if (schema != null && schema != config.database) {
        throw LaconicException(
          'Schema dump history must be in the configured database',
        );
      }
      await (runner ?? const SchemaProcessRunner()).run(
        schemaDumpExecutable,
        [
          ..._schemaArguments(),
          '--no-data',
          '--skip-comments',
          '--skip-add-drop-table',
          if (schemaDialect == 'mysql') '--set-gtid-purged=OFF',
          '--routines',
          '--events',
          config.database,
        ],
        environment: {'MYSQL_PWD': config.password},
        outputPath: path,
      );
    } catch (e) {
      throw _asLaconic(e);
    }
  }

  @override
  Future<void> loadSchema(
    String path, {
    String? schema,
    SchemaProcessRunner? runner,
  }) async {
    try {
      if (schema != null && schema != config.database) {
        throw LaconicException(
          'Schema load history must be in the configured database',
        );
      }
      await (runner ?? const SchemaProcessRunner()).run(
        schemaLoadExecutable,
        [..._schemaArguments(), config.database],
        environment: {'MYSQL_PWD': config.password},
        inputPath: path,
      );
    } catch (e) {
      throw _asLaconic(e);
    }
  }

  @override
  SqlGrammar get grammar => _grammar;

  /// Identifier reported on [LaconicException.driver].
  static const String driverName = 'mysql';

  /// Extracts the MySQL server error code for [LaconicException.code],
  /// or null for client-side and protocol errors which carry no code.
  static String? _errorCode(Object error) =>
      error is MysqlServerException ? '${error.errorCode}' : null;

  LaconicException _asLaconic(Object error) {
    if (error is LaconicException) return error;
    return LaconicException(
      error.toString(),
      driver: driverName,
      code: _errorCode(error),
    );
  }

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
      allowPublicKeyRetrieval: config.allowPublicKeyRetrieval,
      serverPublicKey: config.serverPublicKey,
      connectTimeout: config.connectTimeout,
      commandTimeout: config.commandTimeout,
      onConnectionRemoved: _evictStatementsForConnection,
    );
  }

  /// Returns the pinned transaction connection from the current Zone, if any.
  _MysqlTransaction? get _transactionContext =>
      Zone.current[_txConnKey] as _MysqlTransaction?;

  /// Executes a query, delegating to [_executeOnConn] for protocol selection.
  Future<MysqlResultSet> _executeQuery(String sql, List<Object?> params) async {
    final transaction = _transactionContext ?? _migrationContext;
    if (transaction != null) {
      return transaction.run(
        () => _executeOnConn(transaction.connection, sql, params),
      );
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
    return LaconicResult.fromRows(
      results.columns.map((column) => column.name).toList(),
      results.rows.map((row) => row.toTypedValues()),
    );
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final results = await _executeQuery(sql, params);
      return _toResults(results);
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
  Stream<LaconicResult> selectStream(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final controller = StreamController<LaconicResult>();
    var cancelled = false;

    Future<void> run(MysqlConnection conn) async {
      if (cancelled) return;

      MysqlResultSet? result;
      MysqlPreparedStatement? statement;
      try {
        if (params.isEmpty) {
          result = await conn.execute(sql, null, true);
        } else {
          statement = await conn.prepare(sql, true);
          result = await statement.execute(params);
        }

        final columns = result.columns.map((column) => column.name).toList();
        await controller.addStream(
          result.rowStream.map(
            (row) =>
                LaconicResult.fromRows(columns, [row.toTypedValues()]).single,
          ),
        );
      } catch (e, st) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(_asLaconic(e), st);
        }
      } finally {
        try {
          await statement?.deallocate();
        } catch (_) {
          // Ignore deallocation failures after a cancelled stream.
        }
        if (!cancelled && !controller.isClosed) {
          await controller.close();
        }
      }
    }

    controller.onCancel = () {
      cancelled = true;
    };

    final transaction = _transactionContext ?? _migrationContext;
    if (transaction != null) {
      unawaited(
        transaction.run(() => run(transaction.connection)).catchError((
          Object e,
          StackTrace st,
        ) {
          if (!cancelled && !controller.isClosed) {
            controller.addError(_asLaconic(e), st);
            unawaited(controller.close());
          }
        }),
      );
    } else {
      unawaited(
        _connectionPool.withConnection(run).catchError((
          Object e,
          StackTrace st,
        ) {
          if (!cancelled && !controller.isClosed) {
            controller.addError(_asLaconic(e), st);
            unawaited(controller.close());
          }
        }),
      );
    }

    return controller.stream;
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    try {
      await _executeQuery(sql, params);
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
  Future<int> affectingStatement(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final results = await _executeQuery(sql, params);
      return results.affectedRows.toInt();
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
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final results = await _executeQuery(sql, params);
      return results.lastInsertId.toInt();
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
  Future<T> transaction<T>(Future<T> Function() action) async {
    try {
      if (_transactionContext != null) {
        throw LaconicException('Nested transactions are not supported');
      }
      Future<T> run(MysqlConnection conn) async {
        final transaction = _MysqlTransaction(conn);
        try {
          return await runZoned(action, zoneValues: {_txConnKey: transaction});
        } finally {
          transaction.active = false;
          await transaction.pending;
        }
      }

      final locked = _migrationContext;
      return locked == null
          ? await _connectionPool.transactional(run)
          : await locked.run(() => locked.connection.transactional(run));
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
  Future<T> withMigrationLock<T>(Future<T> Function() action) async {
    try {
      if (_transactionContext != null || _migrationContext != null) {
        throw LaconicException(
          'Migration isolation must start outside a transaction or another migration lock',
        );
      }
      return await _connectionPool.withConnection((conn) async {
        const key = "sha2(concat('laconic-migrations:', database()), 256)";
        final result =
            _toResults(
              await conn.execute('select get_lock($key, 0) as acquired'),
            ).single['acquired'];
        if (result == 0) throw MigrationLockException();
        if (result != 1) {
          throw LaconicException('Could not acquire MySQL migration lock');
        }
        final locked = _MysqlTransaction(conn);
        try {
          return await runZoned(
            action,
            zoneValues: {_migrationConnKey: locked},
          );
        } finally {
          locked.active = false;
          await locked.pending;
          await conn.execute('select release_lock($key)');
        }
      });
    } catch (e) {
      throw _asLaconic(e);
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

class _MysqlTransaction {
  final MysqlConnection connection;
  bool active = true;
  Future<void> pending = Future.value();

  _MysqlTransaction(this.connection);

  Future<T> run<T>(Future<T> Function() action) async {
    if (!active) throw LaconicException('Transaction has already finished');
    final previous = pending;
    final done = Completer<void>();
    pending = done.future;
    await previous;
    try {
      if (!active) throw LaconicException('Transaction has already finished');
      return await action();
    } finally {
      done.complete();
    }
  }
}
