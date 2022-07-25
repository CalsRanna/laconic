import 'package:laconic/src/query_builder.dart';
import 'package:mysql1/mysql1.dart';
import 'package:sqflite/sqflite.dart';

class Database {
  String database;
  String driver;
  String host;
  String password;
  String path;
  int port;
  String username;

  Database({
    required this.database,
    this.driver = 'mysql',
    this.host = 'localhost',
    required this.password,
    this.port = 3306,
    required this.username,
  }) : path = '';

  Database.sqlite({
    this.driver = 'sqflite',
    required this.path,
  })  : database = '',
        host = '',
        port = 3306,
        username = '',
        password = '';

  /// Run a delete statement against the database.
  Future<void> delete(String sql, [List<Object?>? values]) async {
    await _query(sql, values);
  }

  /// Run an insert statement against the database.
  Future<void> insert(String sql, [List<Object?>? values]) async {
    await _query(sql, values);
  }

  /// Run a select statement against the database.
  Future<List<Map<String, Object?>>> select(String sql,
      [List<Object?>? values]) async {
    var rows = await _query(sql, values);
    return rows;
  }

  /// Execute an SQL statement and return the boolean result.
  Future<void> statement(String sql) async {
    await _query(sql);
  }

  /// Get a query builder of the specified table.
  QueryBuilder table(String table) {
    return QueryBuilder.from(db: this, table: table);
  }

  /// Run a raw, unprepared query against the PDO connection.
  Future<void> unprepared(String sql) async {
    await _query(sql);
  }

  /// Run an update statement against the database.
  Future<void> update(String sql, [List<Object?>? values]) async {
    await _query(sql, values);
  }

  Future _query(String sql, [List<Object?>? values]) async {
    if (driver == 'mysql') {
      final connection = await MySqlConnection.connect(ConnectionSettings(
        db: database,
        host: host,
        password: password,
        port: port,
        user: username,
      ));
      try {
        Results results = await connection.query(sql, values);
        await connection.close();
        return results;
      } catch (e) {
        await connection.close();
        rethrow;
      }
    } else {
      final db = await openDatabase(path, version: 1);
      try {
        var results = await db.rawQuery(sql, values);
        await db.close();
        return results;
      } catch (e) {
        await db.close();
        rethrow;
      }
    }
  }
}
