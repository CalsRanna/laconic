import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/src/mysql_config.dart';
import 'package:mysql_client/mysql_client.dart';

/// MySQL driver implementation for Laconic.
///
/// This driver uses the mysql_client package with connection pooling.
/// The connection pool is lazily created on first use.
///
/// Example:
/// ```dart
/// final driver = MysqlDriver(MysqlConfig(
///   database: 'mydb',
///   password: 'secret',
/// ));
/// final db = Laconic(driver);
/// ```
class MysqlDriver implements LaconicDriver {
  final MysqlConfig config;
  MySQLConnectionPool? _pool;

  /// Creates a new MySQL driver with the given configuration.
  MysqlDriver(this.config);

  @override
  Grammar get grammar => SqlGrammar();

  MySQLConnectionPool get _connectionPool {
    return _pool ??= MySQLConnectionPool(
      databaseName: config.database,
      host: config.host,
      maxConnections: 10,
      password: config.password,
      port: config.port,
      userName: config.username,
    );
  }

  /// Converts `?` placeholders to MySQL named parameters (`:p0`, `:p1`, etc.)
  String _convertPlaceholders(String sql, List<Object?> params) {
    if (params.isEmpty) return sql;

    String result = sql;
    for (var i = 0; i < params.length; i++) {
      result = result.replaceFirst('?', ':p$i');
    }
    return result;
  }

  /// Creates a map of named parameters for MySQL.
  Map<String, dynamic> _createNamedParams(List<Object?> params) {
    if (params.isEmpty) return {};
    return Map.fromIterables(
      List.generate(params.length, (i) => 'p$i'),
      params,
    );
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    try {
      final convertedSql = _convertPlaceholders(sql, params);
      final namedParams = _createNamedParams(params);
      final results = await _connectionPool.execute(convertedSql, namedParams);
      return results.rows.map((row) {
        final map = row.typedAssoc();
        return LaconicResult.fromMap(Map<String, Object?>.from(map));
      }).toList();
    } catch (e) {
      throw LaconicException(e.toString());
    }
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    try {
      final convertedSql = _convertPlaceholders(sql, params);
      final namedParams = _createNamedParams(params);
      await _connectionPool.execute(convertedSql, namedParams);
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
      final stmt = await _connectionPool.prepare(sql);
      final results = await stmt.execute(params);
      await stmt.deallocate();
      return results.lastInsertID.toInt();
    } catch (e) {
      throw LaconicException(e.toString());
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    try {
      await _execute('START TRANSACTION');
      final result = await action();
      await _execute('COMMIT');
      return result;
    } catch (e) {
      await _execute('ROLLBACK');
      throw LaconicException(e.toString());
    }
  }

  Future<void> _execute(String sql) async {
    await _connectionPool.execute(sql);
  }

  @override
  Future<void> close() async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
    }
  }
}
