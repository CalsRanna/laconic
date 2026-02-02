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
  TxSession? _transactionSession;
  static final _grammar = PostgresqlGrammar();

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

  /// Converts `?` placeholders to PostgreSQL positional parameters ($1, $2, etc.)
  /// Only converts if the SQL contains `?` placeholders.
  String _convertPlaceholders(String sql) {
    // If SQL already contains positional params ($1, $2, etc.), don't convert
    if (RegExp(r'\$\d+').hasMatch(sql)) {
      return sql;
    }
    int paramIndex = 0;
    return sql.replaceAllMapped(RegExp(r'\?'), (match) {
      paramIndex++;
      return '\$$paramIndex';
    });
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final convertedSql = _convertPlaceholders(sql);

      // Use transaction session if available
      if (_transactionSession != null) {
        final results = await _transactionSession!.execute(
          Sql(convertedSql),
          parameters: params,
        );
        return results.map((row) {
          final map = row.toColumnMap();
          return LaconicResult.fromMap(Map<String, Object?>.from(map));
        }).toList();
      }

      final results = await _connectionPool.execute(
        Sql(convertedSql),
        parameters: params,
      );
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
      final convertedSql = _convertPlaceholders(sql);

      // Use transaction session if available
      if (_transactionSession != null) {
        await _transactionSession!.execute(
          Sql(convertedSql),
          parameters: params,
        );
        return;
      }

      await _connectionPool.execute(Sql(convertedSql), parameters: params);
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
      final convertedSql = _convertPlaceholders(sql);

      Result results;
      // Use transaction session if available
      if (_transactionSession != null) {
        results = await _transactionSession!.execute(
          Sql(convertedSql),
          parameters: params,
        );
      } else {
        results = await _connectionPool.execute(
          Sql(convertedSql),
          parameters: params,
        );
      }

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
          _transactionSession = session;
          try {
            return await action();
          } finally {
            _transactionSession = null;
          }
        });
      });
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> close() async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
    }
  }
}
