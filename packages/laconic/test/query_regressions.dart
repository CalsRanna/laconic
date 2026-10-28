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

  test('where null compiles to IS NULL and IS NOT NULL', () async {
    await query().insert([
      {'id': 90, 'active': 1, 'label': null},
    ]);
    try {
      expect(ids(await query().where('label', null).get()), [90]);
      expect(
        ids(
          await query()
              .where('label', null, comparator: '!=')
              .orderBy('id')
              .get(),
        ),
        [1, 2, 3, 4, 5],
      );
      expect(ids(await query().where('id', 0).orWhere('label', null).get()), [
        90,
      ]);
      expect(
        query().where('label', null).toSql().toLowerCase(),
        contains('is null'),
      );
      expect(
        query().where('label', null, comparator: '!=').toSql().toLowerCase(),
        contains('is not null'),
      );
    } finally {
      await query().where('id', 90).delete();
    }
  });

  test('firstOrNull and findOrNull return null for missing rows', () async {
    expect(await query().where('id', 999).firstOrNull(), isNull);
    expect(await query().findOrNull(999), isNull);
    expect(await query().firstWhereOrNull('id', 999), isNull);
    expect((await query().findOrNull(1))?['label'], '?');
    expect((await query().firstWhereOrNull('id', 2))?['id'], 2);
    await expectLater(
      query().where('id', 999).first(),
      throwsA(isA<LaconicException>()),
    );
    await expectLater(query().find(999), throwsA(isA<LaconicException>()));
  });

  test('selectRaw and groupByRaw accept bindings', () async {
    final row =
        await query().selectRaw('? as marker', [7]).where('id', 1).first();
    expect('${row['marker']}', '7');

    final totals =
        await query()
            .selectRaw('count(*) as total')
            .groupByRaw('active + ?', [0])
            .orderBy('total')
            .get();
    expect(totals.map((r) => '${r['total']}').toList(), ['2', '3']);
  });

  test('update and insert accept raw expression values', () async {
    await query().where('id', 1).update({'label': raw("'raw-label'")});
    try {
      expect(await query().where('id', 1).value('label'), 'raw-label');

      await query().insert([
        {'id': 91, 'active': raw('1'), 'label': raw("'raw-insert'")},
      ]);
      try {
        final row = await query().find(91);
        expect(row['label'], 'raw-insert');
        expect('${row['active']}', '1');
      } finally {
        await query().where('id', 91).delete();
      }
    } finally {
      await query().where('id', 1).update({'label': '?'});
    }
  });

  test('reorder replaces the existing ordering', () async {
    expect(ids(await query().orderBy('id').reorder('id', 'desc').get()), [
      5,
      4,
      3,
      2,
      1,
    ]);
    expect(
      query().orderBy('id').reorder('id', 'desc').toSql(),
      contains('desc'),
    );
  });

  test('aggregates preserve integer results', () async {
    final maxId = await query().max('id');
    expect(maxId, 5);
    expect(maxId, isA<int>());
    expect(await query().sum('id'), 15);
    expect(await query().avg('id'), 3);
  });
}
