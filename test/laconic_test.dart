import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

void main() {
  group('Group of tests on sqlite:', () {
    var config = SqliteConfig('laconic.db');
    final laconic = Laconic.sqlite(config);
    final table = 'user';

    setUp(() {
      laconic.statement('drop table if exists $table');
      laconic.statement(
        'create table $table (id int, name varchar(255), age int, gender varchar(255))',
      );
      laconic.statement(
        'insert into $table (id, name, age, gender) values (?, ?, ?, ?)',
        [1, "John", 25, "male"],
      );
      laconic.statement(
        'insert into $table (id, name, age, gender) values (?, ?, ?, ?)',
        [2, "Jane", 30, "female"],
      );
      laconic.statement(
        'insert into $table (id, name, age, gender) values (?, ?, ?, ?)',
        [3, "Jack", 35, "male"],
      );
    });

    test('select * from users', () async {
      var users = await laconic.select('select * from $table');
      expect(users.length, 3);
    });

    test('select * from users where id = 1', () async {
      var users = await laconic.select('select * from $table where id = ?', [
        1,
      ]);
      expect(users.length, 1);
      expect(users.first['name'], 'John');
    });

    test(
      'insert into $table (id, name, age, gender) values (4, "Tom", 25, "male")',
      () async {
        await laconic.insert(
          'insert into $table (id, name, age, gender) values (?,?,?,?)',
          [4, 'Tom', 25, 'male'],
        );
        var users = await laconic.select('select * from $table');
        expect(users.length, 4);
      },
    );

    test('update users set name = "Jones" where id = 1', () async {
      await laconic.update('update $table set name = ? where id = ?', [
        'Jones',
        1,
      ]);
      var users = await laconic.select('select * from $table where id =?', [1]);
      expect(users.length, 1);
      expect(users.first['name'], 'Jones');
      expect(users.first['age'], 25);
    });

    test('delete from users where id = 1', () async {
      await laconic.delete('delete from $table where id = ?', [1]);
      var users = await laconic.select('select * from $table');
      expect(users.length, 2);
    });

    test('get()', () async {
      var users = await laconic.table(table).get();
      expect(users.length, 3);
    });

    test('where("id", 1).first()', () async {
      var user = await laconic.table(table).where('id', 1).first();
      expect(user['name'], 'John');
    });

    test(
      'insert({"id": 4, "name": "Tom", "age": 25, "gender": "male"})',
      () async {
        await laconic.table(table).insert({
          'id': 4,
          'name': 'Tom',
          'age': 25,
          'gender': 'male',
        });
        var users = await laconic.table(table).get();
        expect(users.length, 4);
      },
    );

    test('where("id", 1).update()', () async {
      await laconic.table(table).where('id', 1).update({'name': 'Jones'});
      var user = await laconic.table(table).where('id', 1).first();
      expect(user['name'], 'Jones');
      expect(user['age'], 25);
    });

    test('where("id", 1).delete()', () async {
      await laconic.table(table).where('id', 1).delete();
      var users = await laconic.table(table).get();
      expect(users.length, 2);
    });
  });
}
