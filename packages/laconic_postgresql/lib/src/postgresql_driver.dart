import 'dart:async';
import 'dart:collection';

import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/src/postgresql_config.dart';
import 'package:laconic_postgresql/src/postgresql_grammar.dart';
import 'package:postgres/postgres.dart';
import 'postgresql_placeholders.dart';

/// PostgreSQL driver implementation for Laconic.
///
/// This driver uses the postgres package with connection pooling.
/// The connection pool is lazily created on first use.
///
/// Example:
/// ```dart
/// final driver = PostgresqlDriver(PostgresqlConfig(
///   database: 'database',
///   password: 'password',
/// ));
/// final laconic = Laconic(driver);
/// ```
class PostgresqlDriver implements DatabaseDriver {
  final PostgresqlConfig config;
  Pool? _pool;
  static final _grammar = PostgresqlGrammar();
  final _txSessionKey = Object();

  final Map<Connection, _PgStatementCache> _stmtCache = {};

  /// Creates a new PostgreSQL driver with the given configuration.
  PostgresqlDriver(this.config);

  @override
  SqlGrammar get grammar => _grammar;

  /// Identifier reported on [LaconicException.driver].
  static const String driverName = 'postgres';

  /// Extracts the SQLSTATE error code for [LaconicException.code],
  /// or null when the error is not a server-reported error.
  static String? _errorCode(Object error) =>
      error is ServerException ? error.code : null;

  LaconicException _asLaconic(Object error) {
    if (error is LaconicException) return error;
    return LaconicException(
      error.toString(),
      driver: driverName,
      code: _errorCode(error),
    );
  }

  Pool get _connectionPool {
    return _pool ??= Pool.withEndpoints(
      [
        Endpoint(
          host: config.host,
          database: config.database,
          username: config.username,
          password: config.password,
          port: config.port,
        ),
      ],
      settings: PoolSettings(
        maxConnectionCount: 10,
        sslMode: config.useSsl ? SslMode.require : SslMode.disable,
      ),
    );
  }

  /// Returns the pinned transaction session from the current Zone, if any.
  _PgTransaction? get _transactionContext =>
      Zone.current[_txSessionKey] as _PgTransaction?;

  Future<Result> _executeQuery(String sql, List<Object?> params) async {
    final convertedSql = PostgresqlPlaceholders.compile(sql, params).sql;
    final transaction = _transactionContext;
    if (transaction != null) {
      if (!transaction.active) {
        throw LaconicException('Transaction has already finished');
      }
      return transaction.cache.execute(convertedSql, params);
    }
    return _connectionPool.withConnection((connection) {
      final cache = _stmtCache.putIfAbsent(connection, () {
        unawaited(
          connection.closed.then(
            (_) {
              _stmtCache.remove(connection);
            },
            onError: (Object error, StackTrace stack) {
              _stmtCache.remove(connection);
            },
          ),
        );
        return _PgStatementCache(connection);
      });
      return cache.execute(convertedSql, params);
    });
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final results = await _executeQuery(sql, params);
      final named = [
        for (var i = 0; i < results.schema.columns.length; i++)
          if (results.schema.columns[i].columnName != null) i,
      ];
      return LaconicResult.fromRows([
        for (final i in named) results.schema.columns[i].columnName!,
      ], results.map((row) => [for (final i in named) row[i]]));
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
    final convertedSql = PostgresqlPlaceholders.compile(sql, params).sql;
    final controller = StreamController<LaconicResult>();
    final done = Completer<void>();
    var cancelled = false;
    ResultStreamSubscription? subscription;

    controller.onCancel = () {
      cancelled = true;
      unawaited(subscription?.cancel());
      if (!done.isCompleted) done.complete();
    };
    controller.onPause = () => subscription?.pause();
    controller.onResume = () => subscription?.resume();

    Future<void> run(Session session) async {
      if (cancelled) return;

      Statement? statement;
      try {
        statement = await session.prepare(Sql(convertedSql));
        final stream = statement.bind(params);

        List<int>? indexes;
        List<String>? columns;

        subscription = stream.listen(
          (row) {
            if (cancelled || controller.isClosed) return;
            controller.add(
              LaconicResult.fromRows(columns!, [
                [for (final i in indexes!) row[i]],
              ]).single,
            );
          },
          onError: (Object e, StackTrace st) {
            if (!cancelled && !controller.isClosed) {
              controller.addError(_asLaconic(e), st);
              unawaited(controller.close());
            }
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!cancelled && !controller.isClosed) {
              unawaited(controller.close());
            }
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );

        subscription!.pause();
        final schema = await Future.any<ResultSchema?>([
          subscription!.schema,
          done.future.then((_) => null),
        ]);
        if (schema == null) return;
        indexes = [
          for (var i = 0; i < schema.columns.length; i++)
            if (schema.columns[i].columnName != null) i,
        ];
        columns = [for (final i in indexes) schema.columns[i].columnName!];
        subscription!.resume();

        await done.future;
      } catch (e, st) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(_asLaconic(e), st);
          await controller.close();
        }
        if (!done.isCompleted) done.complete();
      } finally {
        await subscription?.cancel();
        try {
          await statement?.dispose();
        } catch (_) {
          // Keep the original error if the connection has failed.
        }
      }
    }

    final transaction = _transactionContext;
    if (transaction != null) {
      if (!transaction.active) {
        return Stream.error(
          LaconicException('Transaction has already finished'),
        );
      }
      unawaited(
        run(transaction.cache.session).catchError((Object e, StackTrace st) {
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
      return results.affectedRows;
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

      // PostgreSQL returns the id via RETURNING clause
      if (results.isEmpty) {
        throw LaconicException('Insert did not return an ID');
      }
      final firstRow = results.first;
      if (firstRow.isEmpty) {
        throw LaconicException('Insert returned empty row');
      }
      final id = firstRow[0];
      if (id is! int) {
        throw LaconicException('Insert returned non-integer ID: $id');
      }
      return id;
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
      return await _connectionPool.withConnection((conn) async {
        return await conn.runTx((session) async {
          final transaction = _PgTransaction(_PgStatementCache(session));
          try {
            return await runZoned(
              action,
              zoneValues: {_txSessionKey: transaction},
            );
          } finally {
            transaction.active = false;
            await transaction.cache.dispose();
          }
        });
      });
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
  Future<void> close() async {
    _stmtCache.clear();
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
    }
  }
}

class _PgTransaction {
  final _PgStatementCache cache;
  bool active = true;
  _PgTransaction(this.cache);
}

class _PgStatementCache {
  final Session session;
  final LinkedHashMap<String, Statement> statements = LinkedHashMap();
  Future<void> _tail = Future.value();
  static const _capacity = 50;

  _PgStatementCache(this.session);

  Future<T> _serialized<T>(Future<T> Function() action) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await action();
    } finally {
      done.complete();
    }
  }

  Future<Result> execute(String sql, List<Object?> params) => _serialized(
    () async {
      var statement = statements.remove(sql);
      if (statement == null) {
        if (statements.length >= _capacity) {
          final oldest = statements.remove(statements.keys.first)!;
          await oldest.dispose();
        }
        statement = await session.prepare(Sql(sql));
      }
      statements[sql] = statement;
      try {
        return await statement.run(params);
      } catch (_) {
        statements.remove(sql);
        try {
          await statement.dispose();
        } catch (_) {
          // Keep the original query error if the connection has already failed.
        }
        rethrow;
      }
    },
  );

  Future<void> dispose() => _serialized(() async {
    final pending = statements.values.toList();
    statements.clear();
    for (final statement in pending) {
      await statement.dispose();
    }
  });
}
