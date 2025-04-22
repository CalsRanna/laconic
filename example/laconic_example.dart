import 'package:laconic/laconic.dart';

void main() async {
  final table = 'users';

  // Mysql and query builder
  var mysqlConfig = MysqlConfig(
    database: 'laconic',
    host: '127.0.0.1',
    password: 'root',
    port: 3306,
    username: 'root',
  );
  var laconic = Laconic.mysql(mysqlConfig);

  // Sqlite and query builder
  // var config = SqliteConfig('laconic.db');
  // laconic = Laconic.sqlite(config);

  await laconic.select('select * from $table');
  await laconic.select('select * from $table where id = ?', [1]);
  await laconic.statement(
    'insert into $table (id, name, age, gender) values (?, ?, ?, ?)',
    [4, 'Tom', 25, 'male'],
  );
  await laconic.statement('update $table set name = ? where id = ?', [
    'Jones',
    1,
  ]);
  await laconic.statement('delete from $table where id = ?', [1]);
  await laconic.table(table).get();
  await laconic.table(table).where('id', 1).first();
  await laconic.table(table).insert({
    'id': 4,
    'name': 'Tom',
    'age': 25,
    'gender': 'male',
  });
  await laconic.table(table).where('id', 1).update({'name': 'Jones'});
  await laconic.table(table).where('id', 1).delete();
}
