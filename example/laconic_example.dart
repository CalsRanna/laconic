import 'package:laconic/laconic.dart';

void main() async {
  // Mysql and query builder
  var mysqlConfig = MysqlConfig(
    database: 'laconic',
    host: '127.0.0.1',
    password: 'root',
    port: 3306,
    username: 'root',
  );
  var mysqlLaconic = Laconic.mysql(mysqlConfig);
  await mysqlLaconic.table('users').where('id', 1).first();

  // Sqlite and query builder
  var config = SqliteConfig('laconic.db');
  final sqliteLaconic = Laconic.sqlite(config);
  await sqliteLaconic.table('users').where('id', 1).first();
}
