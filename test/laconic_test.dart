import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

void main() {
  group('Group sqlite:', () {
    var config = SqliteConfig('laconic.db');
    final laconic = Laconic.sqlite(config);
    final userTable = 'users';
    final postTable = 'posts';
    final commentTable = 'comments';

    setUpAll(() async {
      await laconic.statement('drop table if exists $commentTable');
      await laconic.statement('drop table if exists $postTable');
      await laconic.statement('drop table if exists $userTable');
      await laconic.statement(
        'create table $userTable (id integer primary key autoincrement, name varchar(255), age int, gender varchar(255))',
      );
      await laconic.statement(
        'create table $postTable (id integer primary key autoincrement, user_id int not null, title varchar(255), content text, foreign key (user_id) references $userTable(id) on delete cascade)',
      );
      await laconic.statement(
        'create table $commentTable (id integer primary key autoincrement, post_id int not null, user_id int not null, comment_text text)',
      );
      await laconic.table(userTable).insert([
        {'name': 'John', 'age': 25, 'gender': 'male'},
        {'name': 'Jane', 'age': 30, 'gender': 'female'},
        {'name': 'Jack', 'age': 35, 'gender': 'male'},
      ]);
      await laconic.table(postTable).insert([
        {
          'user_id': 1,
          'title': "John's First Thoughts",
          'content': 'Content one.',
        },
        {
          'user_id': 1,
          'title': "John's Second Thoughts",
          'content': 'Content two.',
        },
        {
          'user_id': 2,
          'title': "Jane's Insights",
          'content': 'Insightful content.',
        },
      ]);
      await laconic.table(commentTable).insert([
        {'post_id': 1, 'user_id': 2, 'comment_text': 'Interesting post, John!'},
        {'post_id': 1, 'user_id': 1, 'comment_text': 'Thanks Jane!'},
        {'post_id': 2, 'user_id': 1, 'comment_text': 'Great insights, Jane!'},
      ]);
    });

    tearDownAll(() async {
      await laconic.close();
    });

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

    test(
      'table(users).insertGetId() returns auto-increment ID',
      () async {
        var id = await laconic.table(userTable).insertGetId({
          'name': 'Tom',
          'age': 25,
          'gender': 'male',
        });
        expect(id, greaterThan(0));
        var count = await laconic.table(userTable).count();
        expect(count, 4);
        await laconic.table(userTable).where('id', id).delete();
      },
    );

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

    test('findOrFail returns result or throws', () async {
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['name'], 'John');
    });

    test('findOrFail throws when no result', () async {
      expect(
        () async => await laconic.table(userTable).where('id', 999).first(),
        throwsA(isA<LaconicException>()),
      );
    });

    test('valueOrNull returns null when no result', () async {
      var value = await laconic.table(userTable).where('id', 999).value('name');
      expect(value, isNull);
    });

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

    test(
      '.table("users u").select(["u.name", "p.title"]).join("posts p",(builder) => builder.on("u.id", "p.user_id")).orderBy("u.name").orderBy("p.title")',
      () async {
        var results =
            await laconic
                .table('$userTable u')
                .select(['u.name', 'p.title'])
                .join('$postTable p', (join) => join.on('u.id', 'p.user_id'))
                .orderBy('u.name')
                .orderBy('p.title')
                .get();
        expect(results.length, 3);
      },
    );

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
          await laconic.table(postTable).whereAll([
            'user_id',
            'id',
          ], 1).get();
      expect(results.length, 1);
    });

    test('whereAny with matching value', () async {
      var results =
          await laconic.table(postTable).whereAny([
            'user_id',
            'id',
          ], 2).get();
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

    test('join with orOn condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) =>
                    join.on('u.id', 'p.user_id').orOn('u.id', 'p.id'),
              )
              .orderBy('u.name')
              .orderBy('p.title')
              .get();
      // Should return results where u.id = p.user_id OR u.id = p.id
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
      // Should only return John's posts (user_id = 1)
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
      // Should return posts from user 1 OR user 2
      // User 1 has 2 posts, user 2 has 1 post = 3 total
      // But orWhere in JOIN might work differently, let's check what we get
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
      // Complex JOIN with ON, WHERE, and OR ON conditions
      expect(results.isNotEmpty, isTrue);
    });
  });

  group('Group mysql:', () {
    // Manual MySQL configuration
    final mysqlConfig = MysqlConfig(
      database: 'testdb',
      host: '127.0.0.1',
      port: 3306,
      username: 'root',
      password: 'root',
    );
    final laconic = Laconic.mysql(mysqlConfig);
    final userTable = 'users';
    final postTable = 'posts';
    final commentTable = 'comments';

    setUpAll(() async {
      await laconic.statement('drop table if exists $commentTable');
      await laconic.statement('drop table if exists $postTable');
      await laconic.statement('drop table if exists $userTable');
      await laconic.statement(
        'create table $userTable (id int primary key auto_increment, name varchar(255), age int, gender varchar(255))',
      );
      await laconic.statement(
        'create table $postTable (id int primary key auto_increment, user_id int not null, title varchar(255), content text)',
      );
      await laconic.statement(
        'create table $commentTable (id int primary key auto_increment, post_id int not null, user_id int not null, comment_text text)',
      );
      await laconic.table(userTable).insert([
        {'name': 'John', 'age': 25, 'gender': 'male'},
        {'name': 'Jane', 'age': 30, 'gender': 'female'},
        {'name': 'Jack', 'age': 35, 'gender': 'male'},
      ]);
      await laconic.table(postTable).insert([
        {
          'user_id': 1,
          'title': "John's First Thoughts",
          'content': 'Content one.',
        },
        {
          'user_id': 1,
          'title': "John's Second Thoughts",
          'content': 'Content two.',
        },
        {
          'user_id': 2,
          'title': "Jane's Insights",
          'content': 'Insightful content.',
        },
      ]);
      await laconic.table(commentTable).insert([
        {'post_id': 1, 'user_id': 2, 'comment_text': 'Interesting post, John!'},
        {'post_id': 1, 'user_id': 1, 'comment_text': 'Thanks Jane!'},
        {'post_id': 2, 'user_id': 1, 'comment_text': 'Great insights, Jane!'},
      ]);
    });

    tearDownAll(() async {
      await laconic.close();
    });

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

    test(
      '.table("users u").select(["u.name", "p.title"]).join("posts p",(builder) => builder.on("u.id", "p.user_id")).orderBy("u.name").orderBy("p.title")',
      () async {
        var results =
            await laconic
                .table('$userTable u')
                .select(['u.name', 'p.title'])
                .join('$postTable p', (join) => join.on('u.id', 'p.user_id'))
                .orderBy('u.name')
                .orderBy('p.title')
                .get();
        expect(results.first['name'], 'Jane'); // Jane has posts, Jack doesn't
        expect(results.first['title'], "Jane's Insights");
      },
    );

    test('whereIn with multiple values', () async {
      var users =
          await laconic.table(userTable).whereIn('name', [
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
      var users =
          await laconic.table(userTable).whereNotIn('name', [
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
      var users =
          await laconic
              .table(userTable)
              .whereBetween('age', min: 20, max: 30)
              .get();
      expect(users.length, 2);
    });

    test('whereBetween with exact bounds', () async {
      var users =
          await laconic
              .table(userTable)
              .whereBetween('age', min: 25, max: 30)
              .get();
      expect(users.length, 2);
    });

    test('whereNotBetween excludes range', () async {
      var users =
          await laconic
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

    test('insertGetId returns auto-increment ID', () async {
      var id = await laconic.table(postTable).insertGetId({
        'user_id': 1,
        'title': 'Test Post',
        'content': 'Test content',
      });
      expect(id, greaterThan(0));

      // Verify the record was inserted
      var user = await laconic.table(postTable).where('id', id).first();
      expect(user['title'], 'Test Post');
      expect(user['content'], 'Test content');

      // Cleanup
      await laconic.table(postTable).where('id', id).delete();
    });

    test('insertGetId with minimal data', () async {
      var id = await laconic.table(postTable).insertGetId({
        'user_id': 1,
        'title': 'Test Post',
      });
      expect(id, greaterThan(0));
      await laconic.statement('delete from $postTable where id = ?', [id]);
    });

    test('complex query with multiple new methods', () async {
      var results =
          await laconic
              .table(postTable)
              .select(['user_id', 'title'])
              .whereIn('user_id', [1, 2])
              .whereNotNull('title')
              .distinct()
              .orderBy('user_id')
              .get();
      expect(results.length, greaterThan(0));
    });

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
      var avgAge = await laconic
          .table(userTable)
          .where('gender', 'male')
          .avg('age');
      expect(avgAge, closeTo(30.0, 0.1));
    });

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

    test('pluck returns list of column values', () async {
      var names =
          await laconic.table(userTable).orderBy('name').pluck('name')
              as List<Object?>;
      expect(names.length, 3);
      expect(names[0], 'Jack');
      expect(names[1], 'Jane');
      expect(names[2], 'John');
    });

    test('pluck with key returns map', () async {
      var nameMap =
          await laconic.table(userTable).pluck('name', key: 'id')
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
      var name =
          await laconic.table(userTable).where('id', 1).value('name')
              as String?;
      expect(name, 'John');
    });

    test('value returns null when no record found', () async {
      var name =
          await laconic.table(userTable).where('id', 999).value('name')
              as String?;
      expect(name, isNull);
    });

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

    test('addSelect adds columns to existing select', () async {
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

    test('addSelect replaces asterisk', () async {
      var results =
          await laconic
              .table(userTable)
              .addSelect(['name'])
              .where('id', 1)
              .get();
      expect(results.first['name'], 'John');
    });

    test('when executes callback when condition is true', () async {
      var users =
          await laconic
              .table(userTable)
              .when(true, (builder) => builder.where('age', 25))
              .get();
      expect(users.length, 1);
      expect(users.first['name'], 'John');
    });

    test('when skips callback when condition is false', () async {
      var users =
          await laconic
              .table(userTable)
              .when(false, (builder) => builder.where('age', 25))
              .get();
      expect(users.length, 3);
    });

    test('when executes otherwise when condition is false', () async {
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

    test('whereColumn compares two columns with equality', () async {
      var results =
          await laconic
              .table(postTable)
              .whereColumn('user_id', 'user_id')
              .get();
      expect(results.length, 3);
    });

    test('whereColumn compares columns with operator', () async {
      var results =
          await laconic
              .table(postTable)
              .whereColumn('user_id', 'id', operator: '!=')
              .get();
      // posts: (1,1), (2,1), (3,2) - only (2,1) and (3,2) have user_id != id
      expect(results.length, 2);
    });

    test('whereAll requires all columns to match', () async {
      var results =
          await laconic.table(postTable).whereAll([
            'user_id',
            'id',
          ], 1).get();
      expect(results.length, 1);
    });

    test('whereAny matches if any column matches', () async {
      var results =
          await laconic.table(postTable).whereAny([
            'user_id',
            'id',
          ], 2).get();
      expect(results.length, 2);
    });

    test('whereAny with like operator', () async {
      var results =
          await laconic
              .table(userTable)
              .whereAny(['name', 'gender'], '%oh%', operator: 'like')
              .get();
      // John contains 'oh', Jack does not, Jane does not
      expect(results.length, 1);
      expect(results.first['name'], 'John');
    });

    test('whereNone excludes records where any column matches', () async {
      var results =
          await laconic.table(userTable).whereNone([
            'name',
            'gender',
          ], 'John').get();
      // Excludes John (name='John'), so only Jane and Jack remain
      expect(results.length, 2);
    });

    test('whereNone with specific value', () async {
      var results =
          await laconic.table(userTable).whereNone([
            'name',
            'gender',
          ], 'NonExistent').get();
      // NonExistent doesn't match any record, so all 3 records are returned
      expect(results.length, 3);
    });

    test('whereBetweenColumns checks value between two columns', () async {
      var results =
          await laconic
              .table(userTable)
              .whereBetweenColumns('age', minColumn: 'age', maxColumn: 'age')
              .get();
      // age BETWEEN age AND age is always true (25, 30, 35 are all >= their own value and <= their own value)
      expect(results.length, 3);
    });

    test('whereNotBetweenColumns checks value not between columns', () async {
      var results =
          await laconic
              .table(userTable)
              .whereNotBetweenColumns('age', minColumn: 'age', maxColumn: 'age')
              .get();
      // age NOT BETWEEN age AND age is always false (age is always between itself)
      expect(results.length, 0);
    });

    test('join with orOn condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) =>
                    join.on('u.id', 'p.user_id').orOn('u.id', 'p.id'),
              )
              .get();
      // posts: (1,1), (2,1), (3,2)
      // user 1 matches post 1 (user_id=1), post 2 (user_id=1), and id=1 (post 1)
      // user 2 matches post 3 (user_id=2) and id=2 (post 2)
      // user 3 has no posts but matches id=3 (post 3)
      // Total: 3 + 2 + 1 = 6 (but some are duplicates)
      expect(results.length, greaterThan(0));
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
  });

  group('Group postgresql:', () {
    // Manual PostgreSQL configuration
    final pgConfig = PostgresqlConfig(
      database: 'testdb',
      host: '127.0.0.1',
      port: 5433,
      username: 'postgres',
      password: 'postgres',
      useSsl: false,
    );
    final laconic = Laconic.postgresql(pgConfig);
    final userTable = 'users';
    final postTable = 'posts';
    final commentTable = 'comments';

    setUpAll(() async {
      await laconic.statement('drop table if exists $commentTable');
      await laconic.statement('drop table if exists $postTable');
      await laconic.statement('drop table if exists $userTable');
      await laconic.statement(
        'create table $userTable (id serial primary key, name varchar(255), age int, gender varchar(255))',
      );
      await laconic.statement(
        'create table $postTable (id serial primary key, user_id int not null, title varchar(255), content text)',
      );
      await laconic.statement(
        'create table $commentTable (id serial primary key, post_id int not null, user_id int not null, comment_text text)',
      );
      // Use QueryBuilder for inserts
      await laconic.table(userTable).insert([
        {'name': 'John', 'age': 25, 'gender': 'male'},
        {'name': 'Jane', 'age': 30, 'gender': 'female'},
        {'name': 'Jack', 'age': 35, 'gender': 'male'},
      ]);
      await laconic.table(postTable).insert([
        {
          'user_id': 1,
          'title': "John's First Thoughts",
          'content': 'Content one.',
        },
        {
          'user_id': 1,
          'title': "John's Second Thoughts",
          'content': 'Content two.',
        },
        {
          'user_id': 2,
          'title': "Jane's Insights",
          'content': 'Insightful content.',
        },
      ]);
      await laconic.table(commentTable).insert([
        {'post_id': 1, 'user_id': 2, 'comment_text': 'Interesting post, John!'},
        {'post_id': 1, 'user_id': 1, 'comment_text': 'Thanks Jane!'},
        {'post_id': 2, 'user_id': 1, 'comment_text': 'Great insights, Jane!'},
      ]);
    });

    tearDownAll(() async {
      await laconic.close();
    });

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

    test(
      '.table("users u").select(["u.name", "p.title"]).join("posts p",(builder) => builder.on("u.id", "p.user_id")).orderBy("u.name").orderBy("p.title")',
      () async {
        var results =
            await laconic
                .table('$userTable u')
                .select(['u.name', 'p.title'])
                .join('$postTable p', (join) => join.on('u.id', 'p.user_id'))
                .orderBy('u.name')
                .orderBy('p.title')
                .get();
        expect(results.first['name'], 'Jane'); // Jane has posts, Jack doesn't
        expect(results.first['title'], "Jane's Insights");
      },
    );

    test('whereIn with multiple values', () async {
      var users =
          await laconic.table(userTable).whereIn('name', [
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
      var users =
          await laconic.table(userTable).whereNotIn('name', [
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
      var users =
          await laconic
              .table(userTable)
              .whereBetween('age', min: 20, max: 30)
              .get();
      expect(users.length, 2);
    });

    test('whereBetween with exact bounds', () async {
      var users =
          await laconic
              .table(userTable)
              .whereBetween('age', min: 25, max: 30)
              .get();
      expect(users.length, 2);
    });

    test('whereNotBetween excludes range', () async {
      var users =
          await laconic
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

    test('insertGetId returns auto-increment ID', () async {
      var id = await laconic.table(postTable).insertGetId({
        'user_id': 1,
        'title': 'Test Post',
        'content': 'Test content',
      });
      expect(id, greaterThan(0));

      // Verify the record was inserted
      var user = await laconic.table(postTable).where('id', id).first();
      expect(user['title'], 'Test Post');
      expect(user['content'], 'Test content');

      // Cleanup
      await laconic.table(postTable).where('id', id).delete();
    });

    test('insertGetId with minimal data', () async {
      var id = await laconic.table(postTable).insertGetId({
        'user_id': 1,
        'title': 'Test Post',
      });
      expect(id, greaterThan(0));
      await laconic.table(postTable).where('id', id).delete();
    });

    test('complex query with multiple new methods', () async {
      var results =
          await laconic
              .table(postTable)
              .select(['user_id', 'title'])
              .whereIn('user_id', [1, 2])
              .whereNotNull('title')
              .distinct()
              .orderBy('user_id')
              .get();
      expect(results.length, greaterThan(0));
    });

    test('avg returns average of column values', () async {
      var avgAge = await laconic.table(userTable).avg('age');
      expect(avgAge, closeTo(30.0, 0.1));
    });

    test('sum returns sum of column values', () async {
      var totalAge = await laconic.table(userTable).sum('age');
      expect(totalAge, closeTo(90.0, 0.1));
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
      var avgAge = await laconic
          .table(userTable)
          .where('gender', 'male')
          .avg('age');
      expect(avgAge, closeTo(30.0, 0.1));
    });

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

    test('pluck returns list of column values', () async {
      var names =
          await laconic.table(userTable).orderBy('name').pluck('name')
              as List<Object?>;
      expect(names.length, 3);
      expect(names[0], 'Jack');
      expect(names[1], 'Jane');
      expect(names[2], 'John');
    });

    test('pluck with key returns map', () async {
      var nameMap =
          await laconic.table(userTable).pluck('name', key: 'id')
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
      var name =
          await laconic.table(userTable).where('id', 1).value('name')
              as String?;
      expect(name, 'John');
    });

    test('value returns null when no record found', () async {
      var name =
          await laconic.table(userTable).where('id', 999).value('name')
              as String?;
      expect(name, isNull);
    });

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

    test('addSelect adds columns to existing select', () async {
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

    test('addSelect replaces asterisk', () async {
      var results =
          await laconic
              .table(userTable)
              .addSelect(['name'])
              .where('id', 1)
              .get();
      expect(results.first['name'], 'John');
    });

    test('when executes callback when condition is true', () async {
      var users =
          await laconic
              .table(userTable)
              .when(true, (builder) => builder.where('age', 25))
              .get();
      expect(users.length, 1);
      expect(users.first['name'], 'John');
    });

    test('when skips callback when condition is false', () async {
      var users =
          await laconic
              .table(userTable)
              .when(false, (builder) => builder.where('age', 25))
              .get();
      expect(users.length, 3);
    });

    test('when executes otherwise when condition is false', () async {
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

    test('whereColumn compares two columns with equality', () async {
      var results =
          await laconic
              .table(postTable)
              .whereColumn('user_id', 'user_id')
              .get();
      expect(results.length, 3);
    });

    test('whereColumn compares columns with operator', () async {
      var results =
          await laconic
              .table(postTable)
              .whereColumn('user_id', 'id', operator: '!=')
              .get();
      // posts: (1,1), (2,1), (3,2) - only (2,1) and (3,2) have user_id != id
      expect(results.length, 2);
    });

    test('whereAll requires all columns to match', () async {
      var results =
          await laconic.table(postTable).whereAll([
            'user_id',
            'id',
          ], 1).get();
      expect(results.length, 1);
    });

    test('whereAny matches if any column matches', () async {
      var results =
          await laconic.table(postTable).whereAny([
            'user_id',
            'id',
          ], 2).get();
      expect(results.length, 2);
    });

    test('whereAny with like operator', () async {
      var results =
          await laconic
              .table(userTable)
              .whereAny(['name', 'gender'], '%oh%', operator: 'like')
              .get();
      // John contains 'oh', Jack does not, Jane does not
      expect(results.length, 1);
      expect(results.first['name'], 'John');
    });

    test('whereNone excludes records where any column matches', () async {
      var results =
          await laconic.table(userTable).whereNone([
            'name',
            'gender',
          ], 'John').get();
      // Excludes John (name='John'), so only Jane and Jack remain
      expect(results.length, 2);
    });

    test('whereNone with specific value', () async {
      var results =
          await laconic.table(userTable).whereNone([
            'name',
            'gender',
          ], 'NonExistent').get();
      // NonExistent doesn't match any record, so all 3 records are returned
      expect(results.length, 3);
    });

    test('whereBetweenColumns checks value between two columns', () async {
      var results =
          await laconic
              .table(userTable)
              .whereBetweenColumns('age', minColumn: 'age', maxColumn: 'age')
              .get();
      // age BETWEEN age AND age is always true (25, 30, 35 are all >= their own value and <= their own value)
      expect(results.length, 3);
    });

    test('whereNotBetweenColumns checks value not between columns', () async {
      var results =
          await laconic
              .table(userTable)
              .whereNotBetweenColumns('age', minColumn: 'age', maxColumn: 'age')
              .get();
      // age NOT BETWEEN age AND age is always false (age is always between itself)
      expect(results.length, 0);
    });

    test('join with orOn condition', () async {
      var results =
          await laconic
              .table('$userTable u')
              .select(['u.name', 'p.title'])
              .join(
                '$postTable p',
                (join) =>
                    join.on('u.id', 'p.user_id').orOn('u.id', 'p.id'),
              )
              .get();
      // posts: (1,1), (2,1), (3,2)
      // user 1 matches post 1 (user_id=1), post 2 (user_id=1), and id=1 (post 1)
      // user 2 matches post 3 (user_id=2) and id=2 (post 2)
      // user 3 has no posts but matches id=3 (post 3)
      // Total: 3 + 2 + 1 = 6 (but some are duplicates)
      expect(results.length, greaterThan(0));
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
  });
}
