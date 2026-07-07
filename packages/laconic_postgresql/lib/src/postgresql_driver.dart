import 'dart:async';

import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/src/postgresql_config.dart';
import 'package:laconic_postgresql/src/postgresql_grammar.dart';
import 'package:postgres/postgres.dart';

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
  static final _txSessionKey = Object();

  /// Pre-compiled regex to detect existing $N placeholders in SQL.
  /// Avoids re-compiling the regex on every query.
  static final _positionalParamRE = RegExp(r'\$\d+');

  /// Cache of prepared statements keyed by session hash + SQL.
  final Map<String, dynamic> _stmtCache = {};
  static const int _maxCachedStatements = 50;

  /// Creates a new PostgreSQL driver with the given configuration.
  PostgresqlDriver(this.config);

  @override
  SqlGrammar get grammar => _grammar;

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
  TxSession? get _transactionSession =>
      Zone.current[_txSessionKey] as TxSession?;

  /// Converts `?` placeholders to PostgreSQL positional parameters ($1, $2, etc.)
  /// Only converts if the SQL contains `?` placeholders.
  String _convertPlaceholders(String sql) {
    // Fast path: if there are no '?' characters, no conversion is needed.
    // Grammar-generated SQL uses $N already, so this is the common case.
    if (!sql.contains('?')) return sql;

    // If SQL already contains positional params ($1, $2, etc.), don't convert.
    // This handles raw SQL that uses both $N and ?.
    if (_positionalParamRE.hasMatch(sql)) return sql;

    int paramIndex = 0;
    return sql.replaceAllMapped(RegExp(r'\?'), (match) {
      paramIndex++;
      return '\$$paramIndex';
    });
  }

  /// Runs a prepared statement on a given session.
  ///
  /// Prepared statements are cached to avoid the Parse → Close round-trip
  /// on repeated queries. They are tied to the session they were created on.
  Future<Result> _executeOnConn(
      Session session, String sql, List<Object?> params) async {
    final cacheKey = '${identityHashCode(session)}:$sql';
    dynamic stmt = _stmtCache[cacheKey];
    if (stmt == null) {
      stmt = await session.prepare(Sql(sql));
      if (_stmtCache.length >= _maxCachedStatements) {
        _stmtCache.remove(_stmtCache.keys.first);
      }
      _stmtCache[cacheKey] = stmt;
    }

    try {
      return await stmt.run(params);
    } catch (e) {
      _stmtCache.remove(cacheKey);
      rethrow;
    }
  }

  /// Executes a query using PostgreSQL prepared statements (extended query protocol).
  ///
  /// Uses [Session.prepare] so the SQL is parsed once on the server side and
  /// only parameter values are sent on each execution.
  ///
  /// If a transaction session is active in the current Zone, uses it directly;
  /// otherwise acquires a connection from the pool.
  Future<Result> _executeQuery(String sql, List<Object?> params) async {
    final convertedSql = _convertPlaceholders(sql);
    final txSession = _transactionSession;
    if (txSession != null) {
      return _executeOnConn(txSession, convertedSql, params);
    }
    return _connectionPool.run(
      (session) => _executeOnConn(session, convertedSql, params),
    );
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final results = await _executeQuery(sql, params);
      return results.map((row) {
        final map = row.toColumnMap();
        return LaconicResult.fromMap(Map<String, Object?>.from(map));
      }).toList();
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
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    try {
      return await _connectionPool.withConnection((conn) async {
        return await conn.runTx((session) async {
          return runZoned(() => action(), zoneValues: {_txSessionKey: session});
        });
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
