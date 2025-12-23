import 'package:laconic/src/config/mysql_config.dart';
import 'package:laconic/src/config/postgresql_config.dart';
import 'package:laconic/src/config/sqlite_config.dart';
import 'package:laconic/src/driver.dart';
import 'package:laconic/src/exception.dart';
import 'package:laconic/src/query.dart';
import 'package:laconic/src/query_builder/query_builder.dart';
import 'package:laconic/src/result.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:postgres/postgres.dart';
import 'package:sqlite3/sqlite3.dart';

class Laconic {
  final LaconicDriver driver;
  final void Function(LaconicQuery)? listen;
  final MysqlConfig? mysqlConfig;
  final SqliteConfig? sqliteConfig;
  final PostgresqlConfig? postgresqlConfig;

  MySQLConnectionPool? _pool;
  Database? _database;
  Pool? _pgPool;

  Laconic({
    required this.driver,
    this.listen,
    this.mysqlConfig,
    this.sqliteConfig,
    this.postgresqlConfig,
  }) : assert(
         mysqlConfig != null ||
             sqliteConfig != null ||
             postgresqlConfig != null,
         'At least one database config must be provided',
       ),
       assert(
         driver != LaconicDriver.mysql || mysqlConfig != null,
         'mysqlConfig can not be null while laconic driver is mysql',
       ),
       assert(
         driver != LaconicDriver.sqlite || sqliteConfig != null,
         'sqliteConfig can not be null while laconic driver is sqlite',
       ),
       assert(
         driver != LaconicDriver.postgresql || postgresqlConfig != null,
         'postgresqlConfig can not be null while laconic driver is postgresql',
       );

  Laconic.mysql(MysqlConfig config, {this.listen})
    : driver = LaconicDriver.mysql,
      mysqlConfig = config,
      sqliteConfig = null,
      postgresqlConfig = null;

  Laconic.sqlite(SqliteConfig config, {this.listen})
    : driver = LaconicDriver.sqlite,
      mysqlConfig = null,
      sqliteConfig = config,
      postgresqlConfig = null;

  Laconic.postgresql(PostgresqlConfig config, {this.listen})
    : driver = LaconicDriver.postgresql,
      mysqlConfig = null,
      sqliteConfig = null,
      postgresqlConfig = config;

  Future<void> close() async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
    }
    if (_database != null) {
      _database!.dispose();
      _database = null;
    }
    if (_pgPool != null) {
      await _pgPool!.close();
      _pgPool = null;
    }
  }

  /// Run a select statement against the database.
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    var rows = await _execute(sql, params);
    return rows;
  }

  /// Execute an SQL statement.
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    await _execute(sql, params);
  }

  /// Execute an INSERT statement and return the last inserted ID.
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    listen?.call(LaconicQuery(bindings: params, sql: sql));

    if (driver == LaconicDriver.mysql) {
      _pool ??= MySQLConnectionPool(
        databaseName: mysqlConfig!.database,
        host: mysqlConfig!.host,
        maxConnections: 10,
        password: mysqlConfig!.password,
        port: mysqlConfig!.port,
        userName: mysqlConfig!.username,
      );
      try {
        var stmt = await _pool!.prepare(sql);
        var results = await stmt.execute(params);
        await stmt.deallocate();
        // MySQL returns lastInsertId from the result
        return results.lastInsertID.toInt();
      } catch (error) {
        throw LaconicException(error.toString());
      }
    } else if (driver == LaconicDriver.sqlite) {
      // SQLite
      _database ??= sqlite3.open(sqliteConfig!.path);
      try {
        var stmt = _database!.prepare(sql);
        stmt.execute(params);
        stmt.dispose();
        // Get the last inserted row ID
        final result = _database!.select('SELECT last_insert_rowid() as id');
        return result.first['id'] as int;
      } catch (error) {
        throw LaconicException(error.toString());
      }
    } else {
      // PostgreSQL: Use RETURNING id from the query
      _pgPool ??= Pool.withEndpoints(
        [
          Endpoint(
            host: postgresqlConfig!.host,
            database: postgresqlConfig!.database,
            username: postgresqlConfig!.username,
            password: postgresqlConfig!.password,
            port: postgresqlConfig!.port,
          ),
        ],
        settings: PoolSettings(
          maxConnectionCount: 10,
          sslMode: postgresqlConfig!.useSsl ? SslMode.require : SslMode.disable,
        ),
      );
      try {
        final result = await _pgPool!.execute(sql, parameters: params);
        // PostgreSQL RETURNING id returns the result
        final firstRow = result.first;
        final columnMap = <String, Object?>{};
        final columns = result.schema.columns;
        for (var i = 0; i < columns.length; i++) {
          final colName = columns[i].columnName;
          if (colName != null) {
            columnMap[colName] = firstRow[i];
          }
        }
        final idValue = columnMap['id'];
        if (idValue == null) {
          throw LaconicException('Failed to get inserted ID');
        }
        return idValue as int;
      } catch (error) {
        throw LaconicException(error.toString());
      }
    }
  }

  /// Get a query builder of the specified table.
  QueryBuilder table(String table) {
    return QueryBuilder(laconic: this, table: table);
  }

  Future<T> transaction<T>(Future<T> Function() action) async {
    switch (driver) {
      case LaconicDriver.mysql:
        await _execute('start transaction');
        try {
          final result = await action();
          await _execute('commit');
          return result;
        } catch (error) {
          await _execute('rollback');
          throw LaconicException(error.toString());
        }
      case LaconicDriver.sqlite:
        await _execute('begin transaction');
        try {
          final result = await action();
          await _execute('commit');
          return result;
        } catch (error) {
          await _execute('rollback');
          throw LaconicException(error.toString());
        }
      case LaconicDriver.postgresql:
        await _execute('begin');
        try {
          final result = await action();
          await _execute('commit');
          return result;
        } catch (error) {
          await _execute('rollback');
          throw LaconicException(error.toString());
        }
    }
  }

  Future<List<LaconicResult>> _execute(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    listen?.call(LaconicQuery(bindings: params, sql: sql));
    if (driver == LaconicDriver.mysql) {
      _pool ??= MySQLConnectionPool(
        databaseName: mysqlConfig!.database,
        host: mysqlConfig!.host,
        maxConnections: 10,
        password: mysqlConfig!.password,
        port: mysqlConfig!.port,
        userName: mysqlConfig!.username,
      );
      try {
        // Use direct execute for MySQL (works for both DML and DDL)
        // Convert ? placeholders to :p0, :p1, etc. for named parameters
        String convertedSql = sql;
        Map<String, dynamic>? namedParams;
        if (params.isNotEmpty) {
          for (var i = 0; i < params.length; i++) {
            convertedSql = convertedSql.replaceFirst('?', ':p$i', 0);
          }
          namedParams = Map.fromIterables(
            List.generate(params.length, (i) => 'p$i'),
            params,
          );
        }
        var results = await _pool!.execute(convertedSql, namedParams);
        return results.rows.map(LaconicResult.fromResultSetRow).toList();
      } catch (error) {
        throw LaconicException(error.toString());
      }
    } else if (driver == LaconicDriver.sqlite) {
      _database ??= sqlite3.open(sqliteConfig!.path);
      try {
        var stmt = _database!.prepare(sql);
        var results = stmt.select(params);
        stmt.dispose();
        return results.map(LaconicResult.fromRow).toList();
      } catch (error) {
        throw LaconicException(error.toString());
      }
    } else {
      // PostgreSQL
      _pgPool ??= Pool.withEndpoints(
        [
          Endpoint(
            host: postgresqlConfig!.host,
            database: postgresqlConfig!.database,
            username: postgresqlConfig!.username,
            password: postgresqlConfig!.password,
            port: postgresqlConfig!.port,
          ),
        ],
        settings: PoolSettings(
          maxConnectionCount: 10,
          sslMode: postgresqlConfig!.useSsl ? SslMode.require : SslMode.disable,
        ),
      );
      try {
        // Convert ? placeholders to $1, $2, etc. for PostgreSQL
        String convertedSql = sql;
        if (params.isNotEmpty) {
          var index = 1;
          convertedSql = convertedSql.replaceAllMapped(
            RegExp(r'\?'),
            (match) => '\$${index++}',
          );
        }
        final result = await _pgPool!.execute(convertedSql, parameters: params);
        return result.map((row) {
          final columnMap = <String, Object?>{};
          final columns = result.schema.columns;
          for (var i = 0; i < columns.length; i++) {
            final colName = columns[i].columnName;
            if (colName != null) {
              columnMap[colName] = row[i];
            }
          }
          return LaconicResult.fromMap(columnMap);
        }).toList();
      } catch (error) {
        throw LaconicException(error.toString());
      }
    }
  }
}
