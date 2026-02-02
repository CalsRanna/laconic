import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/src/mysql_config.dart';
import 'package:laconic_mysql/src/mysql_grammar.dart';
import 'package:mysql_client/mysql_client.dart';

/// MySQL driver implementation for Laconic.
///
/// This driver uses the mysql_client package with connection pooling.
/// The connection pool is lazily created on first use.
///
/// Example:
/// ```dart
/// final driver = MysqlDriver(MysqlConfig(
///   database: 'database',
///   password: 'password',
/// ));
/// final laconic = Laconic(driver);
/// ```
class MysqlDriver implements DatabaseDriver {
  final MysqlConfig config;
  MySQLConnectionPool? _pool;
  MySQLConnection? _transactionConnection;
  static final _grammar = MysqlGrammar();

  /// Creates a new MySQL driver with the given configuration.
  MysqlDriver(this.config);

  @override
  SqlGrammar get grammar => _grammar;

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

    int index = 0;
    return sql.replaceAllMapped(RegExp(r'\?'), (match) {
      return ':p${index++}';
    });
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

      // Use transaction connection if available
      if (_transactionConnection != null) {
        final results = await _transactionConnection!.execute(
          convertedSql,
          namedParams,
        );
        return results.rows.map((row) {
          final map = row.typedAssoc();
          return LaconicResult.fromMap(Map<String, Object?>.from(map));
        }).toList();
      }

      final results = await _connectionPool.execute(convertedSql, namedParams);
      return results.rows.map((row) {
        final map = row.typedAssoc();
        return LaconicResult.fromMap(Map<String, Object?>.from(map));
      }).toList();
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    try {
      final convertedSql = _convertPlaceholders(sql, params);
      final namedParams = _createNamedParams(params);

      // Use transaction connection if available
      if (_transactionConnection != null) {
        await _transactionConnection!.execute(convertedSql, namedParams);
        return;
      }

      await _connectionPool.execute(convertedSql, namedParams);
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
      final convertedSql = _convertPlaceholders(sql, params);
      final namedParams = _createNamedParams(params);

      // Use transaction connection if available
      if (_transactionConnection != null) {
        final results =
            await _transactionConnection!.execute(convertedSql, namedParams);
        return results.lastInsertID.toInt();
      }

      final results = await _connectionPool.execute(convertedSql, namedParams);
      return results.lastInsertID.toInt();
    } catch (e, stackTrace) {
      throw LaconicException(e.toString(), cause: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    try {
      return await _connectionPool.transactional((conn) async {
        _transactionConnection = conn;
        try {
          return await action();
        } finally {
          _transactionConnection = null;
        }
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
