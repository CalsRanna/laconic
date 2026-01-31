import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('MySQL:', () {
    final mysqlConfig = MysqlConfig(
      database: 'testdb',
      host: '127.0.0.1',
      port: 3306,
      username: 'root',
      password: 'root',
    );
    final laconic = Laconic(MysqlDriver(mysqlConfig));

    setUpAll(() async {
      await setupMysqlTestData(laconic);
    });

    tearDownAll(() async {
      await laconic.close();
    });

    // ==================== Basic CRUD ====================

    test('select * from users', () async {
      var users = await laconic.table(userTable).get();
      expect(users.length, 3);
    });

    test('select * from users where id = 1', () async {
      var users = await laconic.table(userTable).where('id', 1).get();
      expect(users.length, 1);
      expect(users.first['name'], 'John');
    });

    test('insert into user', () async {
      var id = await laconic.table(userTable).insertGetId({
        'name': 'Tom',
        'age': 25,
        'gender': 'male',
      });
      expect(id, greaterThan(0));
      var count = await laconic.table(userTable).count();
      expect(count, 4);
      await laconic.table(userTable).where('id', id).delete();
    });

    test('update user set name = "Jones" where id = 1', () async {
      await laconic.table(userTable).where('id', 1).update({'name': 'Jones'});
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['name'], 'Jones');
      await laconic.table(userTable).where('id', 1).update({'name': 'John'});
    });

    test('delete from user where id = 99', () async {
      var countBefore = await laconic.table(userTable).count();
      await laconic.table(userTable).where('id', 99).delete();
      var countAfter = await laconic.table(userTable).count();
      expect(countBefore, countAfter);
    });

    test('table(users).get()', () async {
      var users = await laconic.table(userTable).orderBy('id').get();
      expect(users.length, 3);
      expect(users[0]['name'], 'John');
      expect(users[1]['name'], 'Jane');
      expect(users[2]['name'], 'Jack');
    });

    test('table(users).where("id", 1).first()', () async {
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['name'], 'John');
      expect(user['age'], 25);
    });

    test('table(users).insert()', () async {
      var id = await laconic.table(userTable).insertGetId({
        'name': 'Tom',
        'age': 25,
        'gender': 'male',
      });
      expect(id, greaterThan(0));
      var count = await laconic.table(userTable).count();
      expect(count, 4);
      await laconic.table(userTable).where('id', id).delete();
    });

    test('table(users).where("id", 1).update()', () async {
      await laconic.table(userTable).where('id', 1).update({'age': 26});
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['age'], 26);
      await laconic.table(userTable).where('id', 1).update({'age': 25});
    });

    test('table(users).where("id", 99).delete()', () async {
      var countBefore = await laconic.table(userTable).count();
      await laconic.table(userTable).where('id', 99).delete();
      var countAfter = await laconic.table(userTable).count();
      expect(countBefore, countAfter);
    });

    // ==================== WHERE Conditions ====================

    test('whereIn with multiple values', () async {
      var users = await laconic.table(userTable).whereIn('name', [
        'John',
        'Jane',
      ]).get();
      expect(users.length, 2);
    });

    test('whereIn with single value', () async {
      var users =
          await laconic.table(userTable).whereIn('name', ['John']).get();
      expect(users.length, 1);
      expect(users.first['name'], 'John');
    });

    test('whereIn with empty list', () async {
      var users = await laconic.table(userTable).whereIn('name', []).get();
      expect(users.length, 0);
    });

    test('whereNotIn excludes specified values', () async {
      var users = await laconic.table(userTable).whereNotIn('name', [
        'John',
        'Jane',
      ]).get();
      expect(users.length, 1);
      expect(users.first['name'], 'Jack');
    });

    test('whereNotIn with empty list returns all', () async {
      var users = await laconic.table(userTable).whereNotIn('name', []).get();
      expect(users.length, 3);
    });

    test('whereNull finds null values', () async {
      var users = await laconic.table(userTable).whereNull('age').get();
      expect(users.length, 0);
    });

    test('whereNotNull finds non-null values', () async {
      var users = await laconic.table(userTable).whereNotNull('age').get();
      expect(users.length, 3);
    });

    test('whereBetween filters correctly', () async {
      var users = await laconic
          .table(userTable)
          .whereBetween('age', min: 20, max: 30)
          .get();
      expect(users.length, 2);
    });

    test('whereBetween with exact bounds', () async {
      var users = await laconic
          .table(userTable)
          .whereBetween('age', min: 25, max: 30)
          .get();
      expect(users.length, 2);
    });

    test('whereNotBetween excludes range', () async {
      var users = await laconic
          .table(userTable)
          .whereNotBetween('age', min: 20, max: 30)
          .get();
      expect(users.length, 1);
      expect(users.first['name'], 'Jack');
    });

    test('distinct removes duplicates', () async {
      var users = await laconic.table(userTable).distinct().get();
      expect(users.length, 3);
    });

    test('distinct with where clause', () async {
      var users =
          await laconic.table(userTable).where('age', 25).distinct().get();
      expect(users.length, 1);
    });

    // ==================== Insert ====================

    test('insertGetId returns auto-increment ID', () async {
      var id = await laconic.table(postTable).insertGetId({
        'user_id': 1,
        'title': 'Test Post',
        'content': 'Test content',
      });
      expect(id, greaterThan(0));

      var user = await laconic.table(postTable).where('id', id).first();
      expect(user['title'], 'Test Post');
      expect(user['content'], 'Test content');

      await laconic.table(postTable).where('id', id).delete();
    });

    test('complex query with multiple new methods', () async {
      var results = await laconic
          .table(postTable)
          .select(['user_id', 'title'])
          .whereIn('user_id', [1, 2])
          .whereNotNull('title')
          .distinct()
          .orderBy('user_id')
          .get();
      expect(results.length, greaterThan(0));
    });

    // ==================== Aggregates ====================

    test('avg returns average of column values', () async {
      var avgAge = await laconic.table(userTable).avg('age');
      expect(avgAge, closeTo(30.0, 0.1));
    });

    test('sum returns sum of column values', () async {
      var totalAge = await laconic.table(userTable).sum('age');
      expect(totalAge, 90.0);
    });

    test('max returns maximum value', () async {
      var maxAge = await laconic.table(userTable).max('age');
      expect(maxAge, 35.0);
    });

    test('min returns minimum value', () async {
      var minAge = await laconic.table(userTable).min('age');
      expect(minAge, 25.0);
    });

    test('aggregate functions work with where clause', () async {
      var avgAge =
          await laconic.table(userTable).where('gender', 'male').avg('age');
      expect(avgAge, closeTo(30.0, 0.1));
    });

    // ==================== Exists ====================

    test('exists returns true when records exist', () async {
      var hasUsers = await laconic.table(userTable).where('age', 25).exists();
      expect(hasUsers, isTrue);
    });

    test('exists returns false when no records exist', () async {
      var hasUsers = await laconic.table(userTable).where('age', 999).exists();
      expect(hasUsers, isFalse);
    });

    test('doesntExist returns true when no records exist', () async {
      var noUsers =
          await laconic.table(userTable).where('age', 999).doesntExist();
      expect(noUsers, isTrue);
    });

    test('doesntExist returns false when records exist', () async {
      var noUsers =
          await laconic.table(userTable).where('age', 25).doesntExist();
      expect(noUsers, isFalse);
    });

    // ==================== Pluck & Value ====================

    test('pluck returns list of column values', () async {
      var names = await laconic.table(userTable).orderBy('name').pluck('name')
          as List<Object?>;
      expect(names.length, 3);
      expect(names[0], 'Jack');
      expect(names[1], 'Jane');
      expect(names[2], 'John');
    });

    test('pluck with key returns map', () async {
      var nameMap = await laconic.table(userTable).pluck('name', key: 'id')
          as Map<Object?, Object?>;
      expect(nameMap.length, 3);
      expect(nameMap[1], 'John');
      expect(nameMap[2], 'Jane');
      expect(nameMap[3], 'Jack');
    });

    test('pluck works with where clause', () async {
      var names =
          await laconic.table(userTable).where('gender', 'male').pluck('name')
              as List<Object?>;
      expect(names.length, 2);
    });

    test('value returns single column value', () async {
      var name = await laconic.table(userTable).where('id', 1).value('name')
          as String?;
      expect(name, 'John');
    });

    test('value returns null when no record found', () async {
      var name = await laconic.table(userTable).where('id', 999).value('name')
          as String?;
      expect(name, isNull);
    });

    // ==================== Increment/Decrement ====================

    test('increment increases column value', () async {
      await laconic.table(userTable).where('id', 1).increment('age');
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['age'], 26);
      await laconic.table(userTable).where('id', 1).update({'age': 25});
    });

    test('increment with custom amount', () async {
      await laconic.table(userTable).where('id', 1).increment('age', amount: 5);
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['age'], 30);
      await laconic.table(userTable).where('id', 1).update({'age': 25});
    });

    test('increment with extra columns', () async {
      await laconic
          .table(userTable)
          .where('id', 1)
          .increment('age', extra: {'name': 'John_updated'});
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['age'], 26);
      expect(user['name'], 'John_updated');
      await laconic.table(userTable).where('id', 1).update({
        'age': 25,
        'name': 'John',
      });
    });

    test('decrement decreases column value', () async {
      await laconic.table(userTable).where('id', 2).decrement('age');
      var user = await laconic.table(userTable).where('id', 2).first();
      expect(user['age'], 29);
      await laconic.table(userTable).where('id', 2).update({'age': 30});
    });

    test('decrement with custom amount', () async {
      await laconic.table(userTable).where('id', 2).decrement('age', amount: 5);
      var user = await laconic.table(userTable).where('id', 2).first();
      expect(user['age'], 25);
      await laconic.table(userTable).where('id', 2).update({'age': 30});
    });

    // ==================== Advanced WHERE ====================

    test('addSelect adds columns to existing select', () async {
      var results = await laconic
          .table(userTable)
          .select(['name'])
          .addSelect(['age'])
          .where('id', 1)
          .get();
      expect(results.length, 1);
      expect(results.first['name'], 'John');
      expect(results.first['age'], 25);
    });

    test('when executes callback when condition is true', () async {
      var users = await laconic
          .table(userTable)
          .when(true, (builder) => builder.where('age', 25))
          .get();
      expect(users.length, 1);
      expect(users.first['name'], 'John');
    });

    test('when skips callback when condition is false', () async {
      var users = await laconic
          .table(userTable)
          .when(false, (builder) => builder.where('age', 25))
          .get();
      expect(users.length, 3);
    });

    test('when executes otherwise when condition is false', () async {
      var users = await laconic
          .table(userTable)
          .when(
            false,
            (builder) => builder.where('age', 25),
            otherwise: (builder) => builder.where('age', 30),
          )
          .get();
      expect(users.length, 1);
      expect(users.first['name'], 'Jane');
    });

    test('whereColumn compares two columns with equality', () async {
      var results =
          await laconic.table(postTable).whereColumn('user_id', 'user_id').get();
      expect(results.length, 3);
    });

    test('whereColumn compares columns with operator', () async {
      var results = await laconic
          .table(postTable)
          .whereColumn('user_id', 'id', operator: '!=')
          .get();
      expect(results.length, 2);
    });

    test('whereAll requires all columns to match', () async {
      var results = await laconic.table(postTable).whereAll([
        'user_id',
        'id',
      ], 1).get();
      expect(results.length, 1);
    });

    test('whereAny matches if any column matches', () async {
      var results = await laconic.table(postTable).whereAny([
        'user_id',
        'id',
      ], 2).get();
      expect(results.length, 2);
    });

    test('whereAny with like operator', () async {
      var results = await laconic
          .table(userTable)
          .whereAny(['name', 'gender'], '%oh%', operator: 'like')
          .get();
      expect(results.length, 1);
      expect(results.first['name'], 'John');
    });

    test('whereNone excludes records where any column matches', () async {
      var results = await laconic.table(userTable).whereNone([
        'name',
        'gender',
      ], 'John').get();
      expect(results.length, 2);
    });

    test('whereBetweenColumns checks value between two columns', () async {
      var results = await laconic
          .table(userTable)
          .whereBetweenColumns('age', minColumn: 'age', maxColumn: 'age')
          .get();
      expect(results.length, 3);
    });

    test('whereNotBetweenColumns checks value not between columns', () async {
      var results = await laconic
          .table(userTable)
          .whereNotBetweenColumns('age', minColumn: 'age', maxColumn: 'age')
          .get();
      expect(results.length, 0);
    });

    // ==================== JOIN ====================

    test('join with on condition', () async {
      var results = await laconic
          .table('$userTable u')
          .select(['u.name', 'p.title'])
          .join('$postTable p', (join) => join.on('u.id', 'p.user_id'))
          .orderBy('u.name')
          .orderBy('p.title')
          .get();
      expect(results.length, 3);
    });

    test('join with orOn condition', () async {
      var results = await laconic
          .table('$userTable u')
          .select(['u.name', 'p.title'])
          .join(
            '$postTable p',
            (join) => join.on('u.id', 'p.user_id').orOn('u.id', 'p.id'),
          )
          .get();
      expect(results.length, greaterThan(0));
    });

    test('join with where condition', () async {
      var results = await laconic
          .table('$userTable u')
          .select(['u.name', 'p.title'])
          .join(
            '$postTable p',
            (join) => join.on('u.id', 'p.user_id').where('p.user_id', 1),
          )
          .get();
      expect(results.length, 2);
      expect(results.every((r) => r['name'] == 'John'), isTrue);
    });

    test('leftJoin returns all users including those without posts', () async {
      var results = await laconic
          .table('$userTable u')
          .select(['u.name', 'p.title'])
          .leftJoin(
            '$postTable p',
            (join) => join.on('u.id', 'p.user_id'),
          )
          .orderBy('u.name')
          .get();
      expect(results.length, greaterThanOrEqualTo(3));
    });

    test('crossJoin creates cartesian product', () async {
      var results = await laconic
          .table('$userTable u')
          .select(['u.name', 'p.title'])
          .crossJoin('$postTable p')
          .orderBy('u.name')
          .get();
      expect(results.length, 9);
    });

    test('join with whereIn condition', () async {
      var results = await laconic
          .table('$userTable u')
          .select(['u.name', 'p.title'])
          .join(
            '$postTable p',
            (join) => join.on('u.id', 'p.user_id').whereIn('p.user_id', [1, 2]),
          )
          .orderBy('u.name')
          .get();
      expect(results.length, 3);
    });

    test('join with whereNotIn condition', () async {
      var results = await laconic
          .table('$userTable u')
          .select(['u.name', 'p.title'])
          .join(
            '$postTable p',
            (join) => join.on('u.id', 'p.user_id').whereNotIn('p.user_id', [2]),
          )
          .orderBy('u.name')
          .get();
      expect(results.length, 2);
      expect(results.every((r) => r['name'] == 'John'), isTrue);
    });
  });
}
