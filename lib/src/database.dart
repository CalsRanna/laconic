import 'package:laconic/src/query_builder.dart';
import 'package:mysql1/mysql1.dart';

class Database {
  String database;
  String driver;
  String host;
  String password;
  int port;
  String username;

  Database({
    required this.database,
    this.driver = 'mysql',
    this.host = 'localhost',
    required this.password,
    this.port = 3306,
    required this.username,
  });

  /// Run a delete statement against the database.
  Future<int> delete(String sql, [List<Object?>? values]) async {
    Results results = await _query(sql, values);
    return results.affectedRows!;
  }

  /// Run an insert statement against the database.
  Future<int> insert(String sql, [List<Object?>? values]) async {
    Results results = await _query(sql, values);
    return results.affectedRows!;
  }

  /// Run a select statement against the database.
  Future<List<Map<String, dynamic>>> select(String sql,
      [List<Object?>? values]) async {
    Results results = await _query(sql, values);
    List<Map<String, dynamic>> rows = List.empty(growable: true);
    for (ResultRow result in results) {
      rows.add(result.fields);
    }
    return rows;
  }

  /// Execute an SQL statement and return the boolean result.
  Future statement(String sql) async {
    Results results = await _query(sql);
    return results.affectedRows!;
  }

  /// Get a query builder of the specified table.
  QueryBuilder table(String table) {
    return QueryBuilder.from(database: this, table: table);
  }

  /// Run a raw, unprepared query against the PDO connection.
  Future unprepared(String sql) async {
    Results results = await _query(sql);
    return results.affectedRows!;
  }

  /// Run an update statement against the database.
  Future<int> update(String sql, [List<Object?>? values]) async {
    Results results = await _query(sql, values);
    return results.affectedRows!;
  }

  Future<Results> _query(String sql, [List<Object?>? values]) async {
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
  }
}
