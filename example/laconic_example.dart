import 'package:laconic/laconic.dart';

void main() async {
  final userTable = 'users';
  final postTable = 'posts';

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

  await laconic.select('select * from $userTable');
  await laconic.select('select * from $userTable where id = ?', [1]);
  await laconic.statement(
    'insert into $userTable (id, name, age, gender) values (?, ?, ?, ?)',
    [4, 'Tom', 25, 'male'],
  );
  await laconic.statement('update $userTable set name = ? where id = ?', [
    'Jones',
    1,
  ]);
  await laconic.statement('delete from $userTable where id = ?', [1]);
  await laconic.select('''
        select u.name, p.title
        from $userTable u
        join $postTable p on u.id = p.user_id
        order by u.name, p.title
      ''');
  await laconic.table(userTable).get();
  await laconic.table(userTable).where('id', 1).first();
  await laconic.table(userTable).insert([
    {'id': 4, 'name': 'Tom', 'age': 25, 'gender': 'male'},
  ]);
  await laconic.table(userTable).where('id', 1).update({'name': 'Jones'});
  await laconic.table(userTable).where('id', 1).delete();
  await laconic
      .table('$userTable u')
      .select(['u.name', 'p.title'])
      .join('$postTable p', 'u.id', 'p.user_id')
      .orderBy('u.name')
      .orderBy('p.title')
      .get();
  await laconic.close();
}
