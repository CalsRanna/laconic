import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

/// Mock driver for testing the core package without database dependencies.
class MockDriver implements DatabaseDriver {
  final List<String> executedSql = [];
  final List<List<Object?>> executedParams = [];
  List<Map<String, Object?>> mockResults = [];

  @override
  Grammar get grammar => SqlGrammar();

  @override
  Future<List<LaconicResult>> select(String sql,
      [List<Object?> params = const []]) async {
    executedSql.add(sql);
    executedParams.add(params);
    return mockResults.map((r) => LaconicResult.fromMap(r)).toList();
  }

  @override
  Future<void> statement(String sql,
      [List<Object?> params = const []]) async {
    executedSql.add(sql);
    executedParams.add(params);
  }

  @override
  Future<int> insertAndGetId(String sql,
      [List<Object?> params = const []]) async {
    executedSql.add(sql);
    executedParams.add(params);
    return 1;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    return await action();
  }

  @override
  Future<void> close() async {}
}

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
      expect(laconic.grammar, isA<SqlGrammar>());
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

      expect(driver.executedSql.first,
          'insert into users (name, age) values (?, ?)');
      expect(driver.executedParams.first, ['John', 25]);
    });

    test('update query is compiled correctly', () async {
      await laconic.table('users').where('id', 1).update({'name': 'Jane'});

      expect(
          driver.executedSql.first, 'update users set name = ? where id = ?');
      expect(driver.executedParams.first, ['Jane', 1]);
    });

    test('delete query is compiled correctly', () async {
      await laconic.table('users').where('id', 1).delete();

      expect(driver.executedSql.first, 'delete from users where id = ?');
      expect(driver.executedParams.first, [1]);
    });

    test('whereIn compiles correctly', () async {
      await laconic.table('users').whereIn('id', [1, 2, 3]).get();

      expect(driver.executedSql.first,
          'select * from users where id in (?, ?, ?)');
      expect(driver.executedParams.first, [1, 2, 3]);
    });

    test('whereNull compiles correctly', () async {
      await laconic.table('users').whereNull('deleted_at').get();

      expect(
          driver.executedSql.first, 'select * from users where deleted_at is null');
      expect(driver.executedParams.first, isEmpty);
    });

    test('join compiles correctly', () async {
      await laconic
          .table('users u')
          .select(['u.name', 'p.title'])
          .join('posts p', (join) => join.on('u.id', 'p.user_id'))
          .get();

      expect(driver.executedSql.first,
          'select u.name, p.title from users u join posts p on u.id = p.user_id');
    });

    test('listen callback is called', () async {
      final queries = <LaconicQuery>[];
      final listeningLaconic = Laconic(driver, listen: (q) => queries.add(q));

      await listeningLaconic.table('users').get();

      expect(queries.length, 1);
      expect(queries.first.sql, 'select * from users');
    });
  });

  group('PostgreSQL Grammar:', () {
    test('compiles select with positional parameters', () {
      final grammar = PostgresqlGrammar();
      final compiled = grammar.compileSelect(
        table: 'users',
        columns: ['*'],
        wheres: [
          {'type': 'basic', 'column': 'id', 'operator': '=', 'value': 1, 'boolean': 'and'},
        ],
        joins: [],
        orders: [],
        groups: [],
        havings: [],
        distinct: false,
        limit: 10,
        offset: 5,
      );

      expect(compiled.sql,
          'select * from users where id = \$1 limit \$2 offset \$3');
      expect(compiled.bindings, [1, 10, 5]);
    });

    test('compileInsertGetId adds RETURNING clause', () {
      final grammar = PostgresqlGrammar();
      final compiled = grammar.compileInsertGetId(
        table: 'users',
        data: {'name': 'John'},
      );

      expect(compiled.sql, 'insert into users (name) values (\$1) returning id');
      expect(compiled.bindings, ['John']);
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
}
