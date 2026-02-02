import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import 'package:test/test.dart';

import 'test_helper.dart';

void main() {
  group('SQLite:', () {
    final config = SqliteConfig('laconic_test.db');
    final laconic = Laconic(SqliteDriver(config));

    setUpAll(() async {
      await setupSqliteTestData(laconic);
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

    test('table(users).insertGetId() returns auto-increment ID', () async {
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

    // ==================== Aggregates & Helpers ====================

    test('table(users).count()', () async {
      var count = await laconic.table(userTable).count();
      expect(count, 3);
    });

    test('table(users).exists()', () async {
      var exists = await laconic.table(userTable).exists();
      expect(exists, isTrue);
    });

    test('table(users).doesntExist()', () async {
      var doesntExist = await laconic.table(userTable).doesntExist();
      expect(doesntExist, isFalse);
    });

    test('table(users).first() throws when no results', () async {
      expect(
        () async => await laconic.table(userTable).where('id', 999).first(),
        throwsA(isA<LaconicException>()),
      );
    });

    test('table(users).value() returns value', () async {
      var value = await laconic.table(userTable).where('id', 1).value('name');
      expect(value, 'John');
    });

    test('table(users).pluck() returns list', () async {
      var names = await laconic.table(userTable).pluck('name') as List<Object?>;
      expect(names.length, 3);
    });

    test('table(users).pluck(key: "id") returns map', () async {
      var map =
          await laconic.table(userTable).pluck('name', key: 'id')
              as Map<Object?, Object?>;
      expect(map.length, 3);
    });

    test('table(users).avg("age")', () async {
      var avg = await laconic.table(userTable).avg('age');
      expect(avg, closeTo(30.0, 0.1));
    });

    test('table(users).sum("age")', () async {
      var sum = await laconic.table(userTable).sum('age');
      expect(sum, 90.0);
    });

    test('table(users).max("age")', () async {
      var max = await laconic.table(userTable).max('age');
      expect(max, 35.0);
    });

    test('table(users).min("age")', () async {
      var min = await laconic.table(userTable).min('age');
      expect(min, 25.0);
    });

    // ==================== Increment/Decrement ====================

    test('increment without amount', () async {
      await laconic.table(userTable).where('id', 1).increment('age');
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['age'], 26);
      await laconic.table(userTable).where('id', 1).update({'age': 25});
    });

    test('increment with amount', () async {
      await laconic.table(userTable).where('id', 1).increment('age', amount: 5);
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['age'], 30);
      await laconic.table(userTable).where('id', 1).update({'age': 25});
    });

    test('increment with extra', () async {
      await laconic
          .table(userTable)
          .where('id', 1)
          .increment('age', extra: {'name': 'Johnny'});
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['age'], 26);
      expect(user['name'], 'Johnny');
      await laconic.table(userTable).where('id', 1).update({
        'age': 25,
        'name': 'John',
      });
    });

    test('decrement without amount', () async {
      await laconic.table(userTable).where('id', 2).decrement('age');
      var user = await laconic.table(userTable).where('id', 2).first();
      expect(user['age'], 29);
      await laconic.table(userTable).where('id', 2).update({'age': 30});
    });

    test('decrement with amount', () async {
      await laconic.table(userTable).where('id', 2).decrement('age', amount: 5);
      var user = await laconic.table(userTable).where('id', 2).first();
      expect(user['age'], 25);
      await laconic.table(userTable).where('id', 2).update({'age': 30});
    });

    // ==================== WHERE Conditions ====================

    test('select with specific columns', () async {
      var users =
          await laconic
              .table(userTable)
              .select(['name', 'age'])
              .where('id', 1)
              .get();
      expect(users.length, 1);
      expect(users.first['name'], 'John');
      expect(users.first['age'], 25);
    });

    test('select with whereIn', () async {
      var users =
          await laconic.table(userTable).whereIn('name', [
            'John',
            'Jane',
          ]).get();
      expect(users.length, 2);
    });

    test('select with whereNotIn', () async {
      var users =
          await laconic.table(userTable).whereNotIn('name', ['John']).get();
      expect(users.length, 2);
    });

    test('select with whereNull', () async {
      var users = await laconic.table(userTable).whereNull('age').get();
      expect(users.length, 0);
    });

    test('select with whereNotNull', () async {
      var users = await laconic.table(userTable).whereNotNull('age').get();
      expect(users.length, 3);
    });

    test('select with whereBetween', () async {
      var users =
          await laconic
              .table(userTable)
              .whereBetween('age', min: 20, max: 30)
              .get();
      expect(users.length, 2);
    });

    test('select with whereNotBetween', () async {
      var users =
          await laconic
              .table(userTable)
              .whereNotBetween('age', min: 20, max: 30)
              .get();
      expect(users.length, 1);
    });

    test('select with orderBy', () async {
      var users = await laconic.table(userTable).orderBy('age').get();
      expect(users[0]['age'], 25);
      expect(users[1]['age'], 30);
      expect(users[2]['age'], 35);
    });

    test('select with limit', () async {
      var users = await laconic.table(userTable).limit(2).get();
      expect(users.length, 2);
    });

    test('select with offset', () async {
      var users = await laconic.table(userTable).offset(1).limit(2).get();
      expect(users.length, 2);
    });

    test('select with groupBy', () async {
      var users = await laconic.table(userTable).groupBy('gender').get();
      expect(users.length, 2);
    });

    test('select with distinct', () async {
      var users = await laconic.table(userTable).distinct().get();
      expect(users.length, 3);
    });

    // ==================== Advanced WHERE ====================

    test('when true applies condition', () async {
      var users =
          await laconic
              .table(userTable)
              .when(true, (builder) => builder.where('age', 25))
              .get();
      expect(users.length, 1);
      expect(users.first['name'], 'John');
    });

    test('when false skips condition', () async {
      var users =
          await laconic
              .table(userTable)
              .when(false, (builder) => builder.where('age', 25))
              .get();
      expect(users.length, 3);
    });

    test('when with otherwise', () async {
      var users =
          await laconic
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

    test('addSelect adds columns', () async {
      var results =
          await laconic
              .table(userTable)
              .select(['name'])
              .addSelect(['age'])
              .where('id', 1)
              .get();
      expect(results.length, 1);
      expect(results.first['name'], 'John');
      expect(results.first['age'], 25);
    });

    test('whereColumn with equals', () async {
      var results =
          await laconic
              .table(postTable)
              .whereColumn('user_id', 'user_id')
              .get();
      expect(results.length, 3);
    });

    test('whereColumn with not equals', () async {
      var results =
          await laconic
              .table(postTable)
              .whereColumn('user_id', 'id', operator: '!=')
              .get();
      expect(results.length, 2);
    });

    test('whereAll with matching value', () async {
      var results =
          await laconic.table(postTable).whereAll(['user_id', 'id'], 1).get();
      expect(results.length, 1);
    });

    test('whereAny with matching value', () async {
      var results =
          await laconic.table(postTable).whereAny(['user_id', 'id'], 2).get();
      expect(results.length, 2);
    });

    test('whereNone with non-matching value', () async {
      var results =
          await laconic.table(userTable).whereNone([
            'name',
            'gender',
          ], 'John').get();
      expect(results.length, 2);
    });

    test('whereBetweenColumns', () async {
      var users =
          await laconic
              .table(userTable)
              .whereBetweenColumns('age', minColumn: 'age', maxColumn: 'age')
              .get();
      expect(users.length, 3);
    });

    test('whereNotBetweenColumns', () async {
      var users =
          await laconic
              .table(userTable)
              .whereNotBetweenColumns('age', minColumn: 'age', maxColumn: 'age')
              .get();
      expect(users.length, 0);
    });

    // ==================== JOIN ====================

    test('join with on condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join('$postTable p', (join) => join.on('u.id', 'p.user_id'))
              .orderBy('u.name')
              .orderBy('p.title')
              .get();
      expect(results.length, 3);
    });

    test('join with multiple conditions', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join('$postTable p', (join) => join.on('u.id', 'p.user_id'))
              .where('u.age', 25)
              .get();
      expect(results.length, 2);
    });

    test('join with orOn condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) => join.on('u.id', 'p.user_id').orOn('u.id', 'p.id'),
              )
              .orderBy('u.name')
              .orderBy('p.title')
              .get();
      expect(results.isNotEmpty, isTrue);
    });

    test('join with where condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) => join.on('u.id', 'p.user_id').where('p.user_id', 1),
              )
              .orderBy('p.title')
              .get();
      expect(results.length, 2);
      expect(results.every((r) => r['name'] == 'John'), isTrue);
    });

    test('join with orWhere condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) => join
                    .on('u.id', 'p.user_id')
                    .where('p.user_id', 1)
                    .orWhere('p.user_id', 2),
              )
              .orderBy('u.name')
              .orderBy('p.title')
              .get();
      expect(results.isNotEmpty, isTrue);
      expect(results.length, greaterThan(0));
    });

    test('join with complex conditions', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) => join
                    .on('u.id', 'p.user_id')
                    .where('u.age', 25, operator: '>')
                    .orOn('u.id', 'p.id', operator: '='),
              )
              .orderBy('u.name')
              .get();
      expect(results.isNotEmpty, isTrue);
    });

    test('leftJoin returns all users including those without posts', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .leftJoin('$postTable p', (join) => join.on('u.id', 'p.user_id'))
              .orderBy('u.name')
              .get();
      expect(results.length, greaterThanOrEqualTo(3));
    });

    test('crossJoin creates cartesian product', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .crossJoin('$postTable p')
              .orderBy('u.name')
              .get();
      expect(results.length, 9);
    });

    test('join with whereNull condition', () async {
      await laconic.table(postTable).insert([
        {'user_id': 999, 'title': 'Orphan Post', 'content': 'Test'},
      ]);

      var results =
          await laconic
              .table('$postTable p')
              .select(['p.title', 'u.name'])
              .leftJoin('$userTable u', (join) => join.on('p.user_id', 'u.id'))
              .get();
      expect(results.any((r) => r['title'] == 'Orphan Post'), isTrue);

      await laconic.table(postTable).where('title', 'Orphan Post').delete();
    });

    test('join with whereNotNull condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) =>
                    join.on('u.id', 'p.user_id').whereNotNull('p.content'),
              )
              .orderBy('u.name')
              .get();
      expect(results.isNotEmpty, isTrue);
    });

    test('join with whereIn condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) =>
                    join.on('u.id', 'p.user_id').whereIn('p.user_id', [1, 2]),
              )
              .orderBy('u.name')
              .get();
      expect(results.length, 3);
    });

    test('join with whereNotIn condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) =>
                    join.on('u.id', 'p.user_id').whereNotIn('p.user_id', [2]),
              )
              .orderBy('u.name')
              .get();
      expect(results.length, 2);
      expect(results.every((r) => r['name'] == 'John'), isTrue);
    });

    test('join with multiple new conditions', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) => join
                    .on('u.id', 'p.user_id')
                    .whereIn('p.user_id', [1, 2, 3])
                    .whereNotNull('p.title'),
              )
              .orderBy('u.name')
              .get();
      expect(results.length, 3);
    });
  });
}
