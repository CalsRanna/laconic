import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

// The same behavior checks run against each real database driver.
void queryRegressions(Laconic Function() createDatabase) {
  const table = 'laconic_query_regressions';
  late Laconic db;
  QueryBuilder query() => db.table(table);
  List<Object?> ids(List<LaconicResult> rows) => [
    for (final r in rows) r['id'],
  ];
  QueryBuilder union() => query()
      .select(['id', 'label'])
      .where('id', 3)
      .union((q) => q.from(table).select(['id', 'label']).where('id', 1))
      .orderBy('id');

  setUpAll(() async {
    db = createDatabase();
    await db.statement('DROP TABLE IF EXISTS $table');
    await db.statement(
      'CREATE TABLE $table (id INT PRIMARY KEY, active INT, label VARCHAR(20))',
    );
    await query().insert([
      {'id': 1, 'active': 1, 'label': '?'},
      {'id': 2, 'active': 0, 'label': 'two'},
      {'id': 3, 'active': 1, 'label': 'three'},
      {'id': 4, 'active': 0, 'label': 'four'},
      {'id': 5, 'active': 1, 'label': 'five'},
    ]);
  });
  tearDownAll(() async {
    try {
      await db.statement('DROP TABLE IF EXISTS $table');
    } finally {
      await db.close();
    }
  });

  test(
    'empty IN retains OR and nested Boolean semantics for all readers',
    () async {
      final q = query().whereIn('id', []).orWhere('id', 1);
      expect(ids(await q.get()), [1]);
      expect((await q.first())['id'], 1);
      expect((await q.sole())['id'], 1);
      expect(await q.value('id'), 1);
      expect(await q.pluck('id'), [1]);
      expect(await q.pluck('label', key: 'id'), {1: '?'});
      expect(await q.count(), 1);
      expect(await q.sum('id'), 1);
      expect(await q.exists(), isTrue);
      expect(await q.doesntExist(), isFalse);
      final nested = query().whereNested(
        (q) => q.whereIn('id', []).orWhere('id', 2),
      );
      expect(ids(await nested.get()), [2]);
      expect(await query().whereIn('id', []).count(), 0);
      expect(await query().whereIn('id', []).exists(), isFalse);
      expect(await query().whereNotIn('id', []).count(), 5);
    },
  );

  test('chunkById groups OR conditions and visits each row once', () async {
    final seen = <Object?>[];
    await query().where('active', 1).orWhere('active', 0).chunkById(2, (
      rows,
    ) async {
      seen.addAll(ids(rows));
      if (seen.length > 5) fail('Cursor repeated a page: $seen');
    });
    expect(seen, [1, 2, 3, 4, 5]);
  });

  test(
    'chunkById replaces old ordering and applies offset only once',
    () async {
      final q = query().orderByDesc('id').offset(1);
      final before = q.toSql();
      final seen = <Object?>[];
      await q.chunkById(2, (rows) async {
        seen.addAll(ids(rows));
      });
      expect(seen, [2, 3, 4, 5]);
      expect(q.toSql(), before);
    },
  );

  test(
    'chunkById supports table aliases and callbacks that consume their list',
    () async {
      final seen = <Object?>[];
      await db.table('$table t').chunkById(2, (rows) async {
        seen.addAll(ids(rows));
        rows.last.values[0] = -100;
        rows.clear();
      }, alias: 't');
      expect(seen, [1, 2, 3, 4, 5]);
    },
  );

  test('chunk sizes must be positive', () async {
    await expectLater(
      query().chunk(0, (_) async {}),
      throwsA(isA<LaconicException>()),
    );
    await expectLater(
      query().chunkById(-1, (_) async {}),
      throwsA(isA<LaconicException>()),
    );
  });

  test('UNION preserves projection, bindings and final pagination', () async {
    final q = union();
    final rows = await q.get();
    expect(rows.map((r) => r.toMap()), [
      {'id': 1, 'label': '?'},
      {'id': 3, 'label': 'three'},
    ]);
    expect(ids(await db.select(q.toSql(), q.getBindings())), [1, 3]);
    expect(ids(await union().offset(1).limit(1).get()), [3]);
    expect((await union().first())['id'], 1);
    expect(await union().value('label'), '?');
    expect(await union().pluck('id'), [1, 3]);
    expect(await union().pluck('label', key: 'id'), {1: '?', 3: 'three'});
    await expectLater(union().sole(), throwsA(isA<LaconicException>()));
    expect(await union().count(), 2);
    expect(await union().sum('id'), 4);
    expect(await union().min('id'), 1);
    expect(await union().max('id'), 3);
    expect(await union().avg('id'), 2);
  });

  test('UNION ALL retains duplicates and nested branch limits', () async {
    final q = query()
        .select(['id'])
        .where('id', 1)
        .unionAll(
          (q) => q
              .from(table)
              .select(['id'])
              .where('id', 1)
              .unionAll((q) => q.from(table).select(['id']).where('id', 5))
              .orderByDesc('id')
              .limit(1),
        );
    expect(ids(await q.orderBy('id').get()), [1, 5]);
    final duplicates = query()
        .select(['id'])
        .where('id', 1)
        .unionAll((q) => q.from(table).select(['id']).where('id', 1));
    expect(ids(await duplicates.get()), [1, 1]);
    expect(await duplicates.count(), 2);
  });

  test('UNION exists and sole include a nonempty second branch', () async {
    final q = query()
        .select(['id'])
        .where('id', 0)
        .union((q) => q.from(table).select(['id']).where('id', 4));
    expect(await q.exists(), isTrue);
    expect((await q.sole())['id'], 4);
    expect(await q.limit(0).exists(), isFalse);
  });

  test('chunkById applies its cursor to the complete UNION', () async {
    final q = query()
        .select(['id'])
        .where('active', 1)
        .union((q) => q.from(table).select(['id']).where('active', 0));
    final seen = <Object?>[];
    await q.chunkById(2, (rows) async {
      seen.addAll(ids(rows));
      if (seen.length > 5) fail('Cursor repeated a UNION page: $seen');
    });
    expect(seen, [1, 2, 3, 4, 5]);
  });

  test('exists and count retain GROUP BY and HAVING filters', () async {
    final q = query().groupBy('active').havingRaw('COUNT(*) > ?', [10]);
    expect(await q.exists(), isFalse);
    expect(await q.count(), 0);
    final matches = query().groupBy('active').havingRaw('COUNT(*) > ?', [2]);
    expect(await matches.exists(), isTrue);
    expect(await matches.count(), 1);
    final projected = query()
        .select(['active', 'COUNT(*) AS total'])
        .groupBy('active')
        .havingRaw('COUNT(*) > ?', [2]);
    expect(await projected.exists(), isTrue);
    expect(await projected.count(), 1);
    expect(await query().select(['active']).distinct().count(), 2);
  });

  test('EXISTS subqueries retain their group filter and bindings', () async {
    final q = query()
        .where('id', 1)
        .whereExists(
          (q) => q.from(table).where('active', 1).groupBy('active').havingRaw(
            'COUNT(*) > ?',
            [3],
          ),
        );
    expect(await q.get(), isEmpty);
  });

  test(
    'driver rows retain mutable columns and values with duplicate names',
    () async {
      final rows = await db.select(
        'SELECT 1 AS duplicate, 2 AS duplicate, 3 AS other',
      );
      expect(rows.single.toMap(), {'duplicate': 2, 'other': 3});
      rows.single.values[0] = 9;
      expect(rows.single['duplicate'], 9);
      rows.single.columns[0] = 'renamed';
      expect(rows.single['renamed'], 9);
    },
  );
}
