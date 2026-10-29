import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

import 'support/mock_database.dart';

void main() {
  group('Laconic Core:', () {
    late MockDriver driver;
    late Laconic laconic;

    setUp(() {
      driver = MockDriver();
      laconic = Laconic(driver);
    });

    test('table() creates QueryBuilder', () {
      final builder = laconic.table('users');
      expect(builder, isA<QueryBuilder>());
    });

    test('grammar is exposed from driver', () {
      expect(laconic.grammar, isA<MockGrammar>());
    });

    test('select query is compiled correctly', () async {
      driver.mockResults = [
        {'id': 1, 'name': 'John'},
      ];

      final results = await laconic.table('users').where('id', 1).get();

      expect(results.length, 1);
      expect(results.first['name'], 'John');
      expect(driver.executedSql.first, 'select * from users where id = ?');
      expect(driver.executedParams.first, [1]);
    });

    test('insert query is compiled correctly', () async {
      await laconic.table('users').insert([
        {'name': 'John', 'age': 25},
      ]);

      expect(
        driver.executedSql.first,
        'insert into users (name, age) values (?, ?)',
      );
      expect(driver.executedParams.first, ['John', 25]);
    });

    test('update query is compiled correctly', () async {
      driver.affectedRows = 1;
      final affected = await laconic.table('users').where('id', 1).update({
        'name': 'Jane',
      });

      expect(affected, 1);
      expect(
        driver.executedSql.first,
        'update users set name = ? where id = ?',
      );
      expect(driver.executedParams.first, ['Jane', 1]);
    });

    test('delete query is compiled correctly', () async {
      driver.affectedRows = 1;
      final affected = await laconic.table('users').where('id', 1).delete();

      expect(affected, 1);
      expect(driver.executedSql.first, 'delete from users where id = ?');
      expect(driver.executedParams.first, [1]);
    });

    test('whereIn compiles correctly', () async {
      await laconic.table('users').whereIn('id', [1, 2, 3]).get();

      expect(
        driver.executedSql.first,
        'select * from users where id in (?, ?, ?)',
      );
      expect(driver.executedParams.first, [1, 2, 3]);
    });

    test('whereNull compiles correctly', () async {
      await laconic.table('users').whereNull('deleted_at').get();

      expect(
        driver.executedSql.first,
        'select * from users where deleted_at is null',
      );
      expect(driver.executedParams.first, isEmpty);
    });

    test('where with a null value compiles to IS NULL', () async {
      await laconic.table('users').where('deleted_at', null).get();

      expect(
        driver.executedSql.first,
        'select * from users where deleted_at is null',
      );

      await laconic.table('users').where('id', 1, comparator: '!=').get();
      expect(driver.executedSql.last, 'select * from users where id != ?');
    });

    test('invalid comparison operators are rejected', () {
      expect(
        () => laconic.table('users').where('id', 1, comparator: '= 1 or 1 ='),
        throwsA(isA<LaconicException>()),
      );
    });

    test('firstOrNull returns null when no rows match', () async {
      expect(await laconic.table('users').firstOrNull(), isNull);
      expect(await laconic.table('users').findOrNull(999), isNull);
      expect(await laconic.table('users').firstWhereOrNull('id', 999), isNull);

      await expectLater(
        laconic.table('users').first(),
        throwsA(isA<LaconicException>()),
      );
    });

    test('reorder replaces the existing ordering', () async {
      await laconic.table('users').orderBy('id').reorder('name', 'desc').get();

      expect(
        driver.executedSql.first,
        'select * from users order by name desc',
      );
    });

    test('selectRaw bindings precede where bindings', () async {
      await laconic
          .table('users')
          .selectRaw('? as marker', ['x'])
          .where('id', 1)
          .get();

      expect(
        driver.executedSql.first,
        'select ? as marker from users where id = ?',
      );
      expect(driver.executedParams.first, ['x', 1]);
    });

    test('toRawSql escapes string bindings', () {
      final sql = laconic.table('users').where('name', "O'Reilly").toRawSql();
      expect(sql, "select * from users where name = 'O''Reilly'");
    });

    test('limit and offset getters expose current values', () {
      final query = laconic.table('users').limit(3).offset(2);
      expect(query.getLimit(), 3);
      expect(query.getOffset(), 2);
    });

    test('lock accepts bools and validated raw clauses', () {
      expect(
        laconic.table('users').lock('for update nowait').toSql(),
        contains('for update nowait'),
      );
      expect(laconic.table('users').lock(true).toSql(), contains('for update'));
      expect(
        () => laconic.table('users').lock('drop table users'),
        throwsA(isA<LaconicException>()),
      );
    });

    test('join compiles correctly', () async {
      await laconic
          .table('users u')
          .select(['u.name', 'p.title'])
          .join('posts p', (join) => join.on('u.id', 'p.user_id'))
          .get();

      expect(
        driver.executedSql.first,
        'select u.name, p.title from users u join posts p on u.id = p.user_id',
      );
    });

    test('listen callback is called', () async {
      final queries = <LaconicQuery>[];
      final listeningLaconic = Laconic(driver, listen: (q) => queries.add(q));

      await listeningLaconic.table('users').get();

      expect(queries.length, 1);
      expect(queries.first.sql, 'select * from users');
    });

    test('beforeQuery and afterQuery hooks fire', () async {
      final events = <String>[];
      final hooked = Laconic(
        driver,
        beforeQuery: (q) => events.add('before:${q.sql}'),
        afterQuery: (q, elapsed) => events.add('after:${q.sql}'),
      );

      await hooked.table('users').get();

      expect(events, [
        'before:select * from users',
        'after:select * from users',
      ]);
    });
  });

  group('LaconicResult:', () {
    test('operator[] returns value by column name', () {
      final result = LaconicResult.fromMap({'id': 1, 'name': 'John'});
      expect(result['id'], 1);
      expect(result['name'], 'John');
    });

    test('operator[] throws for unknown column', () {
      final result = LaconicResult.fromMap({'id': 1});
      expect(() => result['unknown'], throwsArgumentError);
    });

    test('toMap returns column-value map', () {
      final result = LaconicResult.fromMap({'id': 1, 'name': 'John'});
      expect(result.toMap(), {'id': 1, 'name': 'John'});
    });
  });

  group('LaconicException:', () {
    test('driver and code default to null', () {
      final error = LaconicException('boom');
      expect(error.message, 'boom');
      expect(error.driver, isNull);
      expect(error.code, isNull);
    });

    test('carries driver and code verbatim', () {
      final error = LaconicException('boom', driver: 'mysql', code: '1062');
      expect(error.driver, 'mysql');
      expect(error.code, '1062');
    });

    test('toString is unaffected by driver and code', () {
      final error = LaconicException('boom', driver: 'postgres', code: '23505');
      expect(error.toString(), 'LaconicException: boom');
    });
  });
}
