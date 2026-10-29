import 'package:laconic/laconic.dart';
import 'package:laconic_sqlserver/laconic_sqlserver.dart';
import 'package:laconic_sqlserver/src/sqlserver_placeholders.dart';
import 'package:test/test.dart';

void main() {
  final db = Laconic(
    SqlserverDriver(
      const SqlserverConfig(database: 'testdb', password: 'unused'),
    ),
  );
  QueryBuilder query() => db.table('users');
  final grammar = SqlserverGrammar();

  test('TOP, OFFSET/FETCH and zero limits preserve binding order', () {
    final q = query().selectRaw('? as marker', [7]).where('age', 20).limit(3);
    expect(q.toSql(), 'select top (3) ? as marker from users where age = ?');
    expect(q.getBindings(), [7, 20]);
    final page = q.clone().orderBy('id').offset(5);
    expect(
      page.toSql(),
      endsWith('order by id asc offset ? rows fetch next ? rows only'),
    );
    expect(page.getBindings(), [7, 20, 5, 3]);
    expect(q.clone().offset(5).limit(0).toSql(), contains('top (0)'));
    expect(q.clone().offset(5).limit(0).getBindings(), [7, 20]);
    expect(
      query().offset(2).toSql(),
      endsWith('order by (select 0) offset ? rows'),
    );
  });

  test('ordered derived tables and UNION retain placeholders', () {
    final q = query()
        .fromSub(query().where('age', 20).orderBy('id'), 'u')
        .where('u.id', 4)
        .union(query().where('id', 5))
        .limit(2);
    expect(q.toSql(), contains('order by id asc offset 0 rows'));
    expect(q.getBindings(), [20, 4, 5]);
  });

  test('OUTPUT goes before VALUES including raw expression values', () {
    final c = grammar.compileInsertGetId(
      table: 'users',
      data: {'name': 'a', 'age': raw('20')},
      idColumn: 'user_id',
    );
    expect(
      c.sql,
      'insert into users (name, age) output inserted.user_id values (?, 20)',
    );
    expect(c.bindings, ['a']);
  });

  test('MERGE binds values and respects update columns', () {
    final c = grammar.compileUpsert(
      table: 'users',
      data: [
        {'id': 1, 'name': 'a'},
        {'id': 2, 'name': 'b'},
      ],
      uniqueBy: ['id'],
      update: ['name'],
    );
    expect(c.sql, startsWith('merge into users with (holdlock)'));
    expect(
      c.sql,
      contains('when matched then update set name = laconic_source.name'),
    );
    expect(c.sql, endsWith(';'));
    expect(c.bindings, [1, 'a', 2, 'b']);
    expect(
      grammar
          .compileUpsert(
            table: 'users',
            data: [
              {'id': 1},
            ],
            uniqueBy: ['id'],
            update: [],
          )
          .sql,
      isNot(contains('when matched')),
    );
  });

  test('tuple comparisons expand lexicographically with repeated bindings', () {
    final q = query().whereRowValues(['age', 'id'], '>=', [20, 3]);
    expect(q.toSql(), contains('((age > ?) or (age = ? and id >= ?))'));
    expect(q.getBindings(), [20, 20, 3]);
  });

  test('lock hints follow the table and lateral joins compile to APPLY', () {
    expect(
      query().where('id', 1).lockForUpdate().toSql(),
      contains('from users with (updlock, rowlock) where'),
    );
    expect(query().sharedLock().toSql(), contains('with (holdlock, rowlock)'));
    expect(
      query().joinLateral(query().where('age', 20).limit(1), 'u').toSql(),
      contains('cross apply (select top (1)'),
    );
    expect(
      query().leftJoinLateral(query().limit(1), 'u').toSql(),
      contains('outer apply'),
    );
  });

  test('dialect-specific date, random order and null-safe equality', () {
    expect(
      query().whereDate('created_at', '2026-01-01').toSql(),
      contains('cast(created_at as date) = ?'),
    );
    expect(
      query().whereTime('created_at', '12:00:00').toSql(),
      contains('cast(created_at as time) = ?'),
    );
    expect(query().inRandomOrder().toSql(), contains('newid()'));
    expect(
      query().whereNullSafeEquals('name', null).toSql(),
      contains('is not distinct from ?'),
    );
    expect(
      grammar.compileAggregateExpression('AVG', 'age', distinct: true),
      'AVG(DISTINCT cast(age as float))',
    );
  });

  test('unsupported features fail before executing SQL', () async {
    expect(
      () => query().whereBinary('name', 'a').toSql(),
      throwsA(isA<LaconicException>()),
    );
    expect(
      () => query().useIndex('ix').toSql(),
      throwsA(isA<LaconicException>()),
    );
    expect(
      () => query().whereJsonContains('payload', {'x': 1}).toSql(),
      throwsA(isA<LaconicException>()),
    );
    await expectLater(
      query().insertOrIgnore([
        {'id': 1},
      ]),
      throwsA(isA<LaconicException>()),
    );
    expect(
      () => grammar.compileUpsert(
        table: 'users',
        data: [
          {'id': 1},
        ],
        uniqueBy: [],
      ),
      throwsA(isA<LaconicException>()),
    );
  });

  test('parameter scanner preserves quoted SQL and nested comments', () {
    const sql = '''select '?' as [a?]],b], "c?", 'it''s ?' -- ?
/* ? /* nested ? */ ? */ where id = ? and name = ?''';
    final c = SqlserverPlaceholders.compile(sql, [2, "a' OR 1=1"]);
    expect(c.sql, contains("select '?'"));
    expect(c.sql, contains('/* ? /* nested ? */ ? */'));
    expect(c.sql, endsWith('where id = @laconic_p0 and name = @laconic_p1'));
    expect(c.parameters.values, [2, "a' OR 1=1"]);
  });

  test(
    'parameter scanner rejects mismatches and avoids variable collisions',
    () {
      expect(
        () => SqlserverPlaceholders.compile('select ?', []),
        throwsA(isA<LaconicException>()),
      );
      expect(
        () => SqlserverPlaceholders.compile("select '?'", [1]),
        throwsA(isA<LaconicException>()),
      );
      final c = SqlserverPlaceholders.compile(
        'declare @laconic_p0 int; select ?',
        [1],
      );
      expect(c.parameters.keys.single, 'laconic_p_0');
    },
  );
}
