import 'package:laconic/src/config/mysql_config.dart';
import 'package:laconic/src/config/sqlite_config.dart';
import 'package:laconic/src/driver.dart';
import 'package:laconic/src/exception.dart';
import 'package:laconic/src/query_builder/query_builder.dart';
import 'package:laconic/src/result.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:sqlite3/sqlite3.dart';

class Laconic {
  final LaconicDriver driver;
  final MysqlConfig? mysqlConfig;
  final SqliteConfig? sqliteConfig;

  MySQLConnection? _connection;
  Database? _database;

  Laconic({required this.driver, this.mysqlConfig, this.sqliteConfig})
    : assert(
        mysqlConfig == null && sqliteConfig == null,
        'mysqlConfig and mysqlConfig can not be both null',
      ),
      assert(
        driver == LaconicDriver.mysql && mysqlConfig == null,
        'mysqlConfig can not be null while laconic driver is mysql',
      ),
      assert(
        driver == LaconicDriver.sqlite && sqliteConfig == null,
        'sqliteConfig can not be null while laconic driver is sqlite',
      );

  Laconic.mysql(this.mysqlConfig)
    : driver = LaconicDriver.mysql,
      sqliteConfig = null;

  Laconic.sqlite(this.sqliteConfig)
    : driver = LaconicDriver.sqlite,
      mysqlConfig = null;

  /// Run a delete statement against the database.
  Future<void> delete(String sql, [List<Object?> params = const []]) async {
    await _execute(sql, params);
  }

  /// Run an insert statement against the database.
  Future<void> insert(String sql, [List<Object?> params = const []]) async {
    await _execute(sql, params);
  }

  /// Run a select statement against the database.
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    var rows = await _execute(sql, params);
    return rows;
  }

  /// Execute an SQL statement and return the boolean result.
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    await _execute(sql, params);
  }

  /// Get a query builder of the specified table.
  QueryBuilder table(String table) {
    return QueryBuilder(laconic: this, table: table);
  }

  /// Run a raw, unprepared query against the PDO connection.
  Future<void> unprepared(String sql) async {
    await _execute(sql);
  }

  /// Run an update statement against the database.
  Future<void> update(String sql, [List<Object?> params = const []]) async {
    await _execute(sql, params);
  }

  Future<List<LaconicResult>> _execute(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    print(sql);
    if (driver == LaconicDriver.mysql) {
      _connection ??= await MySQLConnection.createConnection(
        databaseName: mysqlConfig!.database,
        host: mysqlConfig!.host,
        password: mysqlConfig!.password,
        port: mysqlConfig!.port,
        userName: mysqlConfig!.username,
      );
      await _connection!.connect();
      try {
        var stmt = await _connection!.prepare(sql);
        var results = await stmt.execute(params);
        await _connection!.close();
        _connection = null;
        return results.rows.map(LaconicResult.fromResultSetRow).toList();
      } catch (error) {
        await _connection!.close();
        _connection = null;
        throw LaconicException(error.toString());
      }
    } else {
      _database ??= sqlite3.open(sqliteConfig!.path);
      try {
        var results = _database!.select(sql, params);
        _database!.dispose();
        _database = null;
        return results.map(LaconicResult.fromRow).toList();
      } catch (error) {
        _database!.dispose();
        _database = null;
        throw LaconicException(error.toString());
      }
    }
  }
}
