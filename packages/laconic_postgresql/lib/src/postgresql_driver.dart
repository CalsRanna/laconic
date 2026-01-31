import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/src/postgresql_config.dart';
import 'package:postgres/postgres.dart';

/// PostgreSQL driver implementation for Laconic.
///
/// This driver uses the postgres package with connection pooling.
/// The connection pool is lazily created on first use.
///
/// Example:
/// ```dart
/// final driver = PostgresqlDriver(PostgresqlConfig(
///   database: 'mydb',
///   password: 'secret',
/// ));
/// final db = Laconic(driver);
/// ```
class PostgresqlDriver implements DatabaseDriver {
  final PostgresqlConfig config;
  Pool? _pool;

  /// Creates a new PostgreSQL driver with the given configuration.
  PostgresqlDriver(this.config);

  @override
  Grammar get grammar => PostgresqlGrammar();

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
      final results = await _connectionPool.execute(
        Sql(convertedSql),
        parameters: params,
      );
      return results.map((row) {
        final map = row.toColumnMap();
        return LaconicResult.fromMap(Map<String, Object?>.from(map));
      }).toList();
    } catch (e) {
      throw LaconicException(e.toString());
    }
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    try {
      final convertedSql = _convertPlaceholders(sql);
      await _connectionPool.execute(
        Sql(convertedSql),
        parameters: params,
      );
    } catch (e) {
      throw LaconicException(e.toString());
    }
  }

  @override
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final convertedSql = _convertPlaceholders(sql);
      final results = await _connectionPool.execute(
        Sql(convertedSql),
        parameters: params,
      );
      // PostgreSQL returns the id via RETURNING clause
      if (results.isNotEmpty) {
        final firstRow = results.first;
        final id = firstRow[0];
        if (id is int) {
          return id;
        }
      }
      return 0;
    } catch (e) {
      throw LaconicException(e.toString());
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    try {
      return await _connectionPool.withConnection((conn) async {
        return await conn.runTx((session) async {
          return await action();
        });
      });
    } catch (e) {
      throw LaconicException(e.toString());
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
