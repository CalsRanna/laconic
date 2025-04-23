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
      await laconic.statement('''
        create table $userTable (
          id integer primary key,
          name varchar(255),
          age int,
          gender varchar(255)
        )
      ''');
      await laconic.statement('''
        create table $postTable (
          post_id integer primary key autoincrement,
          user_id int not null,
          title varchar(255),
          content text,
          foreign key (user_id) references $userTable(id) on delete cascade
        )
      ''');
      await laconic.statement('''
        create table $commentTable (
          comment_id integer primary key autoincrement,
          post_id int not null,
          user_id int not null, -- User who made the comment
          comment_text text,
          foreign key (post_id) references $postTable(post_id) on delete cascade,
          foreign key (user_id) references $userTable(id) on delete cascade
        )
      ''');
      await laconic.statement(
        'insert into $userTable (id, name, age, gender) values (?, ?, ?, ?)',
        [1, "John", 25, "male"],
      );
      await laconic.statement(
        'insert into $userTable (id, name, age, gender) values (?, ?, ?, ?)',
        [2, "Jane", 30, "female"],
      );
      await laconic.statement(
        'insert into $userTable (id, name, age, gender) values (?, ?, ?, ?)',
        [3, "Jack", 35, "male"],
      );
      await laconic.table(postTable).insert({
        'user_id': 1,
        'title': 'John\'s First Thoughts',
        'content': 'Content one.',
      });
      await laconic.table(postTable).insert({
        'user_id': 1,
        'title': 'John\'s Second Thoughts',
        'content': 'Content two.',
      });
      await laconic.table(postTable).insert({
        'user_id': 2,
        'title': 'Jane\'s Insights',
        'content': 'Insightful content.',
      });
      await laconic.table(commentTable).insert({
        'post_id': 1,
        'user_id': 2,
        'comment_text': 'Interesting post, John!',
      });
      await laconic.table(commentTable).insert({
        'post_id': 1,
        'user_id': 1,
        'comment_text': 'Thanks Jane!',
      });
      await laconic.table(commentTable).insert({
        'post_id': 2,
        'user_id': 1,
        'comment_text': 'Great insights, Jane!',
      });
    });

    tearDownAll(() async {
      await laconic.close();
    });

    test('select * from users', () async {
      var users = await laconic.select('select * from $userTable');
      expect(users.length, 3);
    });

    test('select * from users where id = ?', () async {
      var users = await laconic.select(
        'select * from $userTable where id = ?',
        [1],
      );
      expect(users.length, 1);
      expect(users.first['name'], 'John');
    });

    test(
      'insert into user (id, name, age, gender) values (?, ?, ?, ?)',
      () async {
        await laconic.statement(
          'insert into $userTable (id, name, age, gender) values (?, ?, ?, ?)',
          [4, 'Tom', 25, 'male'],
        );
        var countResult = await laconic.select(
          'select count(*) as count from $userTable',
        );
        expect(countResult.first['count'], 4);
        await laconic.statement('delete from $userTable where id = ?', [4]);
      },
    );

    test('update user set name = "Jones" where id = ?', () async {
      await laconic.statement('update $userTable set name = ? where id = ?', [
        'Jones',
        1,
      ]);
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['name'], 'Jones');
      expect(user['age'], 25);
      await laconic.statement('update $userTable set name = ? where id = ?', [
        'John',
        1,
      ]);
    });

    test('delete from user where id = ?', () async {
      await laconic.statement(
        'insert into $userTable (id, name, age, gender) values (?, ?, ?, ?)',
        [99, 'Temp User', 40, 'other'],
      );
      var countBefore =
          (await laconic.select(
                'select count(*) as c from $userTable',
              )).first['c']
              as int;
      await laconic.statement('delete from $userTable where id = ?', [99]);
      var countAfter =
          (await laconic.select(
                'select count(*) as c from $userTable',
              )).first['c']
              as int;
      expect(countAfter, countBefore - 1);
      var users = await laconic.select(
        'select * from $userTable where id = ?',
        [99],
      );
      expect(users.isEmpty, isTrue);
    });

    test(
      'select u.name, p.title from users u join posts p on u.id = p.user_id order by u.name, p.title',
      () async {
        final results = await laconic.select('''
        select u.name, p.title
        from $userTable u
        join $postTable p on u.id = p.user_id
        order by u.name, p.title
      ''');
        expect(results.length, 3);
        expect(results[0]['name'], 'Jane');
        expect(results[0]['title'], 'Jane\'s Insights');
        expect(results[1]['name'], 'John');
        expect(results[1]['title'], 'John\'s First Thoughts');
        expect(results[2]['name'], 'John');
        expect(results[2]['title'], 'John\'s Second Thoughts');
      },
    );

    test('table(users).get()', () async {
      var users = await laconic.table(userTable).get();
      expect(users.length, 3);
    });

    test('table(users).where("id", 1).first()', () async {
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['name'], 'John');
    });

    test(
      'table(users).insert({"id": 4, "name": "Tom", "age": 25, "gender": "male"})',
      () async {
        await laconic.table(userTable).insert({
          'id': 4,
          'name': 'Tom',
          'age': 25,
          'gender': 'male',
        });
        var countResult = await laconic.select(
          'select count(*) as count from $userTable',
        );
        expect(countResult.first['count'], 4);
        await laconic.table(userTable).where('id', 4).delete();
      },
    );

    test('table(users).where("id", 1).update()', () async {
      await laconic.table(userTable).where('id', 1).update({'name': 'Jones'});
      var user = await laconic.table(userTable).where('id', 1).first();
      expect(user['name'], 'Jones');
      expect(user['age'], 25);
      await laconic.table(userTable).where('id', 1).update({'name': 'John'});
    });

    test('table(users).where("id", 99).delete()', () async {
      await laconic.table(userTable).insert({
        'id': 99,
        'name': 'Temp User',
        'age': 40,
        'gender': 'other',
      });
      var countBefore = (await laconic.table(userTable).count());
      await laconic.table(userTable).where('id', 99).delete();
      var countAfter = (await laconic.table(userTable).count());
      expect(countAfter, countBefore - 1);
    });

    test(
      '.table("users u").select(["u.name", "p.title"]).join("posts p",(builder) => builder.on("u.id", "p.user_id")).orderBy("u.name").orderBy("p.title")',
      () async {
        var results =
            await laconic
                .table('$userTable u')
                .select(['u.name', 'p.title'])
                .join(
                  '$postTable p',
                  (builder) => builder.on('u.id', 'p.user_id'),
                )
                .orderBy('u.name')
                .orderBy('p.title')
                .get();
        expect(results.length, 3);
        expect(results[0]['name'], 'Jane');
        expect(results[0]['title'], 'Jane\'s Insights');
        expect(results[1]['name'], 'John');
        expect(results[1]['title'], 'John\'s First Thoughts');
        expect(results[2]['name'], 'John');
        expect(results[2]['title'], 'John\'s Second Thoughts');
      },
    );
  });
}
