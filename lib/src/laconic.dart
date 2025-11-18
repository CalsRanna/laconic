import 'package:laconic/src/config/mysql_config.dart';
import 'package:laconic/src/config/sqlite_config.dart';
import 'package:laconic/src/driver.dart';
import 'package:laconic/src/exception.dart';
import 'package:laconic/src/query.dart';
import 'package:laconic/src/query_builder/query_builder.dart';
import 'package:laconic/src/result.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:sqlite3/sqlite3.dart';

class Laconic {
  final LaconicDriver driver;
  final void Function(LaconicQuery)? listen;
  final MysqlConfig? mysqlConfig;
  final SqliteConfig? sqliteConfig;

  MySQLConnectionPool? _pool;
  Database? _database;

  Laconic({
    required this.driver,
    this.listen,
    this.mysqlConfig,
    this.sqliteConfig,
  }) : assert(
         mysqlConfig != null || sqliteConfig != null,
         'mysqlConfig and mysqlConfig can not be both null',
       ),
       assert(
         driver != LaconicDriver.mysql || mysqlConfig != null,
         'mysqlConfig can not be null while laconic driver is mysql',
       ),
       assert(
         driver != LaconicDriver.sqlite || sqliteConfig != null,
         'sqliteConfig can not be null while laconic driver is sqlite',
       );

  Laconic.mysql(MysqlConfig config, {this.listen})
    : driver = LaconicDriver.mysql,
      mysqlConfig = config,
      sqliteConfig = null;

  Laconic.sqlite(SqliteConfig config, {this.listen})
    : driver = LaconicDriver.sqlite,
      mysqlConfig = null,
      sqliteConfig = config;

  Future<void> close() async {
    if (_pool != null) {
      await _pool!.close();
      _pool = null;
    }
    if (_database != null) {
      _database!.dispose();
      _database = null;
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
    } else {
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
    }
  }

  /// Get a query builder of the specified table.
  QueryBuilder table(String table) {
    return QueryBuilder(laconic: this, table: table);
  }

  Future<T> transaction<T>(Future<T> Function() action) async {
    if (driver == LaconicDriver.mysql) {
      await _execute('start transaction');
      try {
        final result = await action();
        await _execute('commit');
        return result;
      } catch (error) {
        await _execute('rollback');
        throw LaconicException(error.toString());
      }
    } else {
      await _execute('begin transaction');
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
        var stmt = await _pool!.prepare(sql);
        var results = await stmt.execute(params);
        await stmt.deallocate();
        return results.rows.map(LaconicResult.fromResultSetRow).toList();
      } catch (error) {
        throw LaconicException(error.toString());
      }
    } else {
      _database ??= sqlite3.open(sqliteConfig!.path);
      try {
        var stmt = _database!.prepare(sql);
        var results = stmt.select(params);
        stmt.dispose();
        return results.map(LaconicResult.fromRow).toList();
      } catch (error) {
        throw LaconicException(error.toString());
      }
    }
  }
}
