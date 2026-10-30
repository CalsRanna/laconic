import 'dart:async';

import 'package:laconic/laconic.dart';
import 'package:mssql/mssql.dart';

import 'sqlserver_config.dart';
import 'sqlserver_grammar.dart';
import 'sqlserver_placeholders.dart';

/// SQL Server driver with lazy pooling and a connection pinned per transaction.
class SqlserverDriver implements DatabaseDriver, MigrationLockDriver {
  final SqlserverConfig config;
  MssqlPool? _pool;
  static final _grammar = SqlserverGrammar();
  static const driverName = 'sqlserver';
  final _transactionKey = Object();
  final _migrationKey = Object();
  _SqlserverTransaction? get _migrationContext =>
      Zone.current[_migrationKey] as _SqlserverTransaction?;

  SqlserverDriver(this.config);

  @override
  SqlGrammar get grammar => _grammar;

  MssqlPool get _connectionPool =>
      _pool ??= MssqlPool(
        MssqlPoolConfig(
          host: config.host,
          port: config.port,
          database: config.database,
          user: config.username,
          password: config.password,
          encrypt: config.useSsl,
          trustServerCertificate: config.allowBadCertificates,
          max: config.maxConnections,
          connectionTimeout: config.connectTimeout,
          acquireTimeout: config.acquireTimeout,
        ),
      );

  _SqlserverTransaction? get _transaction =>
      Zone.current[_transactionKey] as _SqlserverTransaction?;

  LaconicException _error(Object error) {
    if (error is LaconicException) return error;
    return LaconicException(
      error.toString(),
      driver: driverName,
      code: error is MssqlException ? '${error.errorCode}' : null,
    );
  }

  Future<T> _withConnection<T>(
    Future<T> Function(MssqlConnection) action,
  ) async {
    final transaction = _transaction ?? _migrationContext;
    if (transaction != null) {
      return transaction.run(() => action(transaction.connection));
    }
    final pool = _connectionPool;
    final connection = await pool.acquire();
    try {
      return await action(connection);
    } finally {
      pool.release(connection);
    }
  }

  @override
  Future<T> withMigrationLock<T>(Future<T> Function() action) async {
    try {
      if (_transaction != null || _migrationContext != null) {
        throw LaconicException(
          'Migration isolation must start outside a transaction or another migration lock',
        );
      }
      return await _withConnection((conn) async {
        final acquired = await conn.query(
          "declare @result int; exec @result = sp_getapplock @Resource = N'laconic-migrations', @LockMode = 'Exclusive', @LockOwner = 'Session', @LockTimeout = 0; select @result as acquired",
        );
        final code = acquired.rows.single.valueAt(0) as int;
        if (code == -1) throw MigrationLockException();
        if (code < 0) {
          throw LaconicException(
            'Could not acquire SQL Server migration lock: $code',
          );
        }
        final locked = _SqlserverTransaction(conn);
        try {
          return await runZoned(action, zoneValues: {_migrationKey: locked});
        } finally {
          locked.active = false;
          await locked.pending;
          await conn.query(
            "exec sp_releaseapplock @Resource = N'laconic-migrations', @LockOwner = 'Session'",
          );
        }
      });
    } catch (e) {
      throw _error(e);
    }
  }

  Future<MssqlResult> _query(String sql, List<Object?> params) {
    final bound = SqlserverPlaceholders.compile(sql, params);
    return _withConnection((conn) => conn.query(bound.sql, bound.parameters));
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final result = await _query(sql, params);
      return LaconicResult.fromRows(
        result.columns.map((c) => c.name).toList(),
        result.rows.map((r) => List<Object?>.of(r.values)),
      );
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw _error(e);
    }
  }

  @override
  Stream<LaconicResult> selectStream(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final controller = StreamController<LaconicResult>();
    StreamSubscription<MssqlRow>? subscription;
    var cancelled = false;
    final drained = Completer<void>();
    // Capture the transaction zone when the stream is created.
    final zone = Zone.current;
    controller.onListen = () {
      zone.run(() async {
        try {
          final bound = SqlserverPlaceholders.compile(sql, params);
          await _withConnection((connection) async {
            if (cancelled) return;
            subscription = connection
                .queryStream(bound.sql, bound.parameters)
                .listen(
                  (row) {
                    if (!cancelled) {
                      controller.add(
                        LaconicResult.fromRows(row.columnNames, [
                          List<Object?>.of(row.values),
                        ]).single,
                      );
                    }
                  },
                  onError: (Object e, StackTrace st) {
                    if (!cancelled) controller.addError(_error(e), st);
                  },
                  onDone: () => drained.complete(),
                );
            if (controller.isPaused && !cancelled) subscription!.pause();
            await drained.future;
          });
        } catch (e, st) {
          if (!cancelled) controller.addError(_error(e), st);
        } finally {
          if (!drained.isCompleted) drained.complete();
          if (!cancelled) unawaited(controller.close());
        }
      });
    };
    controller.onPause = () => subscription?.pause();
    controller.onResume = () => subscription?.resume();
    controller.onCancel = () {
      // The client closes a connection when its stream is cancelled. Drain the
      // remaining rows instead, keeping a pinned transaction usable and returning
      // a clean connection to the pool. No remaining rows are retained.
      cancelled = true;
      subscription?.resume();
      return drained.future;
    };
    return controller.stream;
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    try {
      await _query(sql, params);
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw _error(e);
    }
  }

  @override
  Future<int> affectingStatement(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      return (await _query(sql, params)).rowsAffected;
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw _error(e);
    }
  }

  @override
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final result = await _query(sql, params);
      if (result.rows.length != 1 || result.rows.single.valueAt(0) is! int) {
        throw LaconicException(
          'SQL Server insertGetId requires one integer OUTPUT ID',
        );
      }
      return result.rows.single.valueAt(0) as int;
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw _error(e);
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    try {
      if (_transaction != null) {
        throw LaconicException('Nested transactions are not supported');
      }
      return await _withConnection((connection) async {
        await connection.beginTransaction();
        final transaction = _SqlserverTransaction(connection);
        try {
          final result = await runZoned(
            action,
            zoneValues: {_transactionKey: transaction},
          );
          transaction.active = false;
          await transaction.pending;
          await connection.commitTransaction();
          return result;
        } catch (e) {
          transaction.active = false;
          await transaction.pending;
          try {
            await connection.rollbackTransaction();
          } catch (rollbackError) {
            throw LaconicException(
              '$e; rollback failed: $rollbackError',
              driver: driverName,
            );
          }
          rethrow;
        }
      });
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw _error(e);
    }
  }

  @override
  Future<void> close() async {
    try {
      final pool = _pool;
      _pool = null;
      await pool?.close();
    } catch (e) {
      if (e is LaconicException) rethrow;
      throw _error(e);
    }
  }
}

class _SqlserverTransaction {
  final MssqlConnection connection;
  bool active = true;
  Future<void> pending = Future.value();

  _SqlserverTransaction(this.connection);

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
