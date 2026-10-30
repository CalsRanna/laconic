import 'package:laconic/laconic.dart';
import 'package:test/test.dart';
import 'query_semantics_regressions.dart';
import 'query_result_regressions.dart';
import 'query_pagination_regressions.dart';

// The same behavior checks run against each real database driver.

abstract final class QueryRegressions {
  static void register(
    Laconic Function() createDatabase, {
    bool supportsInsertOrIgnore = true,
    bool supportsOrderedWrites = true,
    bool supportsWriteOffset = false,
    bool supportsLimitedJoinWrites = true,
    int upsertUpdateCount = 1,
  }) {
    QueryResultRegressions.register(
      createDatabase,
      supportsInsertOrIgnore: supportsInsertOrIgnore,
      upsertUpdateCount: upsertUpdateCount,
    );
    QueryPaginationRegressions.register(createDatabase);
    QuerySemanticsRegressions.register(
      createDatabase,
      supportsOrderedWrites: supportsOrderedWrites,
      supportsWriteOffset: supportsWriteOffset,
      supportsLimitedJoinWrites: supportsLimitedJoinWrites,
    );
    const table = 'laconic_query_regressions';
    const jsonTable = 'laconic_json_probe';
    const groupLimitTable = 'laconic_group_limit_probe';
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

      await db.statement('DROP TABLE IF EXISTS $jsonTable');
      await db.statement(
        'CREATE TABLE $jsonTable (id INT PRIMARY KEY, tags TEXT, payload TEXT)',
      );
      await db.table(jsonTable).insert([
        {
          'id': 1,
          'tags': '["a","b"]',
          'payload': '{"name":"John","count":2,"tags":["a","b"]}',
        },
        {
          'id': 2,
          'tags': '["b","c"]',
          'payload': '{"name":"Jane","count":1,"tags":["b","c"]}',
        },
        {
          'id': 3,
          'tags': '["d"]',
          'payload': '{"name":"Jack","count":3,"tags":["d"]}',
        },
      ]);

      await db.statement('DROP TABLE IF EXISTS $groupLimitTable');
      await db.statement(
        'CREATE TABLE $groupLimitTable '
        '(id INT PRIMARY KEY, grp VARCHAR(10), val INT)',
      );
      await db.table(groupLimitTable).insert([
        {'id': 1, 'grp': 'a', 'val': 10},
        {'id': 2, 'grp': 'a', 'val': 20},
        {'id': 3, 'grp': 'a', 'val': 30},
        {'id': 4, 'grp': 'b', 'val': 1},
        {'id': 5, 'grp': 'b', 'val': 2},
      ]);
    });
    tearDownAll(() async {
      try {
        await db.statement('DROP TABLE IF EXISTS $groupLimitTable');
        await db.statement('DROP TABLE IF EXISTS $jsonTable');
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
        }, column: 't.id');
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
          .select(['active', const Expression('COUNT(*) AS total')])
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

    test('bound raw groups support count and existence queries', () async {
      final grouped = query().groupByRaw('active + ?', [0]);
      expect(await grouped.count(), 2);
      expect(await grouped.exists(), isTrue);
      expect(await grouped.clone().distinct().count(), 2);
      expect(await grouped.clone().havingRaw('count(*) > ?', [2]).count(), 1);
      expect(
        await grouped.clone().havingRaw('count(*) > ?', [2]).exists(),
        isTrue,
      );
      expect(await grouped.clone().where('id', 99).count(), 0);
      expect(await grouped.clone().where('id', 99).exists(), isFalse);
      expect(
        await query()
            .whereExists(
              (q) => q.from(table).groupByRaw('active + ?', [0]).havingRaw(
                'count(*) > ?',
                [2],
              ),
            )
            .count(),
        5,
      );
    });

    test('offset works without an explicit limit', () async {
      expect(await query().orderBy('id').offset(2).pluck('id'), [3, 4, 5]);
      expect(await query().orderBy('id').skip(0).pluck('id'), [1, 2, 3, 4, 5]);
      expect(await query().orderBy('id').offset(2).limit(0).get(), isEmpty);
      expect(ids(await union().offset(1).get()), [3]);
    });

    test('update and insert accept raw expression values', () async {
      await query().where('id', 1).update({'label': Expression("'raw-label'")});
      try {
        expect(await query().where('id', 1).value('label'), 'raw-label');

        await query().insert([
          {
            'id': 91,
            'active': Expression('1'),
            'label': Expression("'raw-insert'"),
          },
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

    test('negated nested groups and orWhereNone execute', () async {
      expect(
        ids(
          await query()
              .where('active', 1)
              .whereNot((q) => q.where('id', 1).orWhere('id', 3))
              .get(),
        ),
        [5],
      );
      expect(
        ids(
          await query()
              .where('id', 1)
              .orWhereNone(['active'], 0)
              .orderBy('id')
              .get(),
        ),
        [1, 3, 5],
      );
    });

    test('whereIntegerInRaw interpolates integers without bindings', () async {
      final q = query().whereIntegerInRaw('id', [1, 3]);
      expect(ids(await q.orderBy('id').get()), [1, 3]);
      expect(q.getBindings(), isEmpty);
      expect(
        ids(
          await query().whereIntegerNotInRaw('id', [1, 3]).orderBy('id').get(),
        ),
        [2, 4, 5],
      );
      expect(await query().whereIntegerInRaw('id', []).count(), 0);
      expect(await query().whereIntegerNotInRaw('id', []).count(), 5);
    });

    test('whereRowValues compares tuples', () async {
      expect(
        ids(await query().whereRowValues(['id', 'active'], '=', [1, 1]).get()),
        [1],
      );
      expect(
        await query().whereRowValues(['id', 'active'], '=', [1, 0]).count(),
        0,
      );
      expect(
        () => query().whereRowValues(['id'], '=', [1, 2]),
        throwsA(isA<LaconicException>()),
      );
      expect(
        () => query().whereRowValues([], '=', []),
        throwsA(isA<LaconicException>()),
      );
      expect(
        () => query().whereValueBetween(1, ['id']),
        throwsA(isA<LaconicException>()),
      );
    });

    test('whereValueBetween compares a value against two columns', () async {
      expect(ids(await query().whereValueBetween(2, ['id', 'id']).get()), [2]);
      expect(await query().whereValueNotBetween(2, ['id', 'id']).count(), 4);
    });

    test('whereNullSafeEquals matches NULL', () async {
      await query().insert([
        {'id': 93, 'active': 1, 'label': null},
      ]);
      try {
        expect(ids(await query().whereNullSafeEquals('label', null).get()), [
          93,
        ]);
        expect(ids(await query().whereNullSafeEquals('label', 'two').get()), [
          2,
        ]);
        expect(
          await query().whereNullSafeEquals('label', 'missing').count(),
          0,
        );
      } finally {
        await query().where('id', 93).delete();
      }
    });

    test('having between, null and nested variants execute', () async {
      final groups =
          await query()
              .selectRaw('active, count(*) as total')
              .groupBy('active')
              .havingBetween(const Expression('count(*)'), min: 2, max: 3)
              .orderBy('active')
              .get();
      expect(groups.length, 2);
      expect(groups.map((r) => '${r['total']}').toList(), ['2', '3']);

      expect(
        await query()
            .groupBy('active')
            .havingNull(const Expression('count(*)'))
            .count(),
        0,
      );
      expect(
        await query()
            .groupBy('active')
            .havingNotNull(const Expression('count(*)'))
            .count(),
        2,
      );

      final nested =
          await query()
              .groupBy('active')
              .havingNested(
                (q) => q
                    .having(const Expression('count(*)'), 2, comparator: '>=')
                    .orHaving(
                      const Expression('count(*)'),
                      3,
                      comparator: '>=',
                    ),
              )
              .count();
      expect(nested, 2);
    });

    test('updateOrInsert updates or inserts a row', () async {
      await query().insert([
        {'id': 94, 'active': 1, 'label': 'before'},
      ]);
      try {
        expect(
          await query().updateOrInsert({'id': 94}, {'label': 'after'}),
          isTrue,
        );
        expect(await query().where('id', 94).value('label'), 'after');

        expect(
          await query().updateOrInsert(
            {'id': 95},
            {'active': 1, 'label': 'new'},
          ),
          isTrue,
        );
        expect(await query().where('id', 95).value('label'), 'new');
      } finally {
        await query().whereIn('id', [94, 95]).delete();
      }
    });

    test('incrementEach and decrementEach adjust multiple columns', () async {
      const probe = 'laconic_adjust_probe';
      await db.statement('drop table if exists $probe');
      await db.statement(
        'create table $probe (id int primary key, a int, b int)',
      );
      try {
        await db.table(probe).insert([
          {'id': 1, 'a': 10, 'b': 20},
        ]);

        await db.table(probe).where('id', 1).incrementEach({'a': 5, 'b': 2});
        var row = await db.table(probe).find(1);
        expect(row['a'], 15);
        expect(row['b'], 22);

        await db.table(probe).where('id', 1).decrementEach({'a': 3, 'b': 1});
        row = await db.table(probe).find(1);
        expect(row['a'], 12);
        expect(row['b'], 21);

        await db
            .table(probe)
            .where('id', 1)
            .incrementEach({'a': 1}, extra: {'b': Expression('b + 10')});
        row = await db.table(probe).find(1);
        expect(row['a'], 13);
        expect(row['b'], 31);

        await expectLater(
          db.table(probe).incrementEach({'a': 1}),
          throwsA(isA<LaconicException>()),
        );
      } finally {
        await db.statement('drop table if exists $probe');
      }
    });

    test('soleValue, implode, existsOr and pagination getters work', () async {
      expect(await query().where('id', 1).soleValue('label'), '?');
      await expectLater(
        query().where('id', 999).soleValue('label'),
        throwsA(isA<LaconicException>()),
      );

      expect(
        await query().orderBy('id').implode('label', '|'),
        '?|two|three|four|five',
      );

      expect(await query().where('id', 1).existsOr(() => false), isTrue);
      expect(await query().where('id', 999).existsOr(() => false), isFalse);
      expect(await query().where('id', 999).doesntExistOr(() => false), isTrue);
      expect(await query().where('id', 1).doesntExistOr(() => false), isFalse);

      final paginated = query().limit(2).offset(1);
      expect(paginated.getLimit(), 2);
      expect(paginated.getOffset(), 1);
    });

    test('joinWhere joins on a bound value', () async {
      final rows =
          await db
              .table('$table u')
              .select(['u.id'])
              .joinWhere('$table p', 'p.id', '=', 1)
              .get();
      expect(rows.length, 5);
    });

    test('toRawSql substitutes bindings', () async {
      final sql = query().where('id', 1).where('label', "O'Reilly").toRawSql();
      expect(sql, contains('${db.grammar.wrap('id')} = 1'));
      expect(sql, contains("${db.grammar.wrap('label')} = 'O''Reilly'"));
    });

    test('inOrderOf orders by the given values', () async {
      expect(await query().inOrderOf('id', [3, 1, 5, 2, 4]).pluck('id'), [
        3,
        1,
        5,
        2,
        4,
      ]);
    });

    test('forPageAfterId and forPageBeforeId use keyset pagination', () async {
      expect(ids(await query().forPageAfterId(2, 2).get()), [3, 4]);
      expect(ids(await query().forPageBeforeId(2, 4).get()), [3, 2]);
      expect(ids(await query().forPageAfterId(2, null).get()), [1, 2]);
    });

    test('union accepts a QueryBuilder directly', () async {
      final branch = query().select(['id']).where('id', 1);
      final unionQuery = query()
          .select(['id'])
          .where('id', 3)
          .union(branch)
          .orderBy('id');
      expect(ids(await unionQuery.get()), [1, 3]);

      final all = query()
          .select(['id'])
          .where('id', 1)
          .unionAll(query().select(['id']).where('id', 1));
      expect(ids(await all.get()), [1, 1]);
    });

    test('firstOr and findOr return fallbacks', () async {
      final fallback = LaconicResult.fromMap({'id': 0, 'label': 'fallback'});
      expect(
        (await query().where('id', 1).firstOr(() => fallback))['label'],
        '?',
      );
      expect(
        (await query().where('id', 999).firstOr(() => fallback))['label'],
        'fallback',
      );
      expect((await query().findOr(999, () => fallback))['label'], 'fallback');
      expect((await query().findOrFail(1))['id'], 1);
      await expectLater(
        query().findOrFail(999),
        throwsA(isA<LaconicException>()),
      );
      await expectLater(
        query().where('id', 999).firstOrFail(),
        throwsA(isA<LaconicException>()),
      );
    });

    test('insert returns true', () async {
      expect(
        await query().insert([
          {'id': 97, 'active': 0, 'label': 'inserted'},
        ]),
        isTrue,
      );
      await query().where('id', 97).delete();
    });

    test('whereMap and case-insensitive whereLike work', () async {
      expect(await query().whereMap({'id': 1, 'active': 1}).count(), 1);
      expect(await query().whereMap({'id': 1, 'active': 0}).count(), 0);
      expect(
        ids(
          await query().whereLike('label', 'TWO', caseSensitive: false).get(),
        ),
        [2],
      );
      expect(
        await query()
            .whereNotLike('label', 'TWO', caseSensitive: false)
            .count(),
        4,
      );
    });

    test('distinct with columns selects distinct values', () async {
      final rows = await query().distinct(['active']).orderBy('active').get();
      expect(rows.map((r) => '${r['active']}').toList(), ['0', '1']);
    });

    test('distinct aggregates ignore duplicate input values', () async {
      final q = query().distinct();
      expect(await q.sum('active'), 1);
      expect(await q.avg('active'), 0.5);
      expect(await q.min('active'), 0);
      expect(await q.max('active'), 1);
      expect(await q.clone().where('id', 0).sum('active'), 0);
      expect(await query().sum('active'), 3);
      expect(await query().avg('active'), closeTo(0.6, 0.000001));
    });

    test(
      'column readers resolve qualified columns and selected aliases',
      () async {
        final q = db
            .table('$table t')
            .join('$table r', (join) => join.on('t.id', 'r.id'))
            .orderBy('t.id');
        expect(await q.pluck('t.id'), [1, 2, 3, 4, 5]);
        expect(await q.pluck('t.label', key: 'r.id'), {
          1: '?',
          2: 'two',
          3: 'three',
          4: 'four',
          5: 'five',
        });
        expect(await q.pluck('t.id as selected_id'), [1, 2, 3, 4, 5]);
        expect(await q.value('t.label'), '?');
        expect(await q.value('t.label as selected_label'), '?');
        expect(await q.clone().where('t.id', 1).soleValue('t.label'), '?');
        final page = await q.cursorPaginate(2, column: 't.id');
        expect(ids(page.data), [1, 2]);
        expect(page.nextCursor?.parameters.values, [2]);
      },
    );

    test('count supports column and distinct forms', () async {
      await query().insert([
        {'id': 98, 'active': 1, 'label': null},
      ]);
      try {
        expect(await query().count(), 6);
        expect(await query().count('id'), 6);
        expect(await query().count('label'), 5);
        expect(await query().distinct().count(), 6);
        expect(await query().distinct(['active']).count(), 2);
        expect(await query().distinct().count('active'), 2);
      } finally {
        await query().where('id', 98).delete();
      }
    });

    test('selectSub embeds a correlated subquery', () async {
      final rows =
          await db
              .table('$table u')
              .select(['u.id'])
              .selectSub(
                (q) => q
                    .from('$table p')
                    .selectRaw('count(*)')
                    .whereColumn('p.id', 'u.id')
                    .where('p.active', 1),
                'matches',
              )
              .orderBy('u.id')
              .get();
      expect(rows.map((r) => '${r['matches']}').toList(), [
        '1',
        '0',
        '1',
        '0',
        '1',
      ]);
    });

    test('selectSub handles multiple subqueries with bindings', () async {
      final rows =
          await db
              .table(table)
              .select(['id'])
              .selectSub(
                (q) => q.from(table).selectRaw('count(*)').where('active', 1),
                'active_count',
              )
              .selectSub(
                (q) => q.from(table).selectRaw('count(*)').where('active', 0),
                'inactive_count',
              )
              .where('id', 1)
              .get();
      expect('${rows.first['active_count']}', '3');
      expect('${rows.first['inactive_count']}', '2');
    });

    test('fromSub and fromRaw accept bindings', () async {
      final fromSubRows =
          await db
              .table(table)
              .select(['id'])
              .selectRaw('? as marker', [7])
              .fromSub(
                (q) => q.from(table).select(['id', 'label']).where('active', 1),
                't',
              )
              .where('t.id', 3)
              .get();
      expect(ids(fromSubRows), [3]);
      expect('${fromSubRows.first['marker']}', '7');

      final fromSubQuery = db
          .table(table)
          .fromSub(
            (q) => q.from(table).select(['id', 'label']).where('active', 1),
            't',
          );
      expect(await fromSubQuery.clone().count(), 3);
      expect(await fromSubQuery.clone().max('t.id'), 5);

      final fromRawRows =
          await db
              .table(table)
              .fromRaw('(select id, label from $table where active = ?) as t', [
                1,
              ])
              .where('t.id', 5)
              .get();
      expect(ids(fromRawRows), [5]);
    });

    test('joinSub joins a derived table', () async {
      final rows =
          await db
              .table('$table u')
              .select(['u.id'])
              .selectRaw('? as marker', [7])
              .joinSub(
                (q) => q.from(table).select(['id']).where('active', 1),
                'p',
                'p.id',
                '=',
                'u.id',
              )
              .orderBy('u.id')
              .get();
      expect(ids(rows), [1, 3, 5]);
      expect(rows.every((r) => '${r['marker']}' == '7'), isTrue);

      final crossCount =
          await db
              .table(table)
              .crossJoinSub(
                (q) => q.from(table).select(['id']).where('active', 1),
                'p',
              )
              .count();
      expect(crossCount, 15);

      final whereJoin =
          await db
              .table('$table u')
              .select(['u.id'])
              .joinSub(
                (q) => q.from(table).select(['id']).where('id', 1),
                'p',
                'u.active',
                '>=',
                0,
                where: true,
              )
              .count();
      expect(whereJoin, 5);
    });

    test('whereIn and whereNotIn accept subqueries', () async {
      final selected = query().whereIn(
        'id',
        (q) => q.from(table).select(['id']).where('active', 1),
      );
      expect(ids(await selected.orderBy('id').get()), [1, 3, 5]);

      expect(
        ids(
          await query()
              .whereNotIn('id', query().select(['id']).where('active', 1))
              .orderBy('id')
              .get(),
        ),
        [2, 4],
      );

      final withPriorBinding = query()
          .where('active', 1)
          .whereIn(
            'id',
            (q) => q.from(table).select(['id']).where('label', 'three'),
          );
      expect(ids(await withPriorBinding.get()), [3]);
    });

    test('where accepts a subquery as a value', () async {
      final q = query()
          .where('id', 0, comparator: '>')
          .where(
            'id',
            (q) => q.from(table).selectRaw('max(id)').where('active', 0),
            comparator: '>',
          );
      expect(ids(await q.get()), [5]);
    });

    test('insertUsing inserts rows from a subquery', () async {
      const probe = 'laconic_insert_using_probe';
      await db.statement('drop table if exists $probe');
      await db.statement(
        'create table $probe (id int primary key, label varchar(20))',
      );
      try {
        final inserted = await db.table(probe).insertUsing([
          'id',
          'label',
        ], query().select(['id', 'label']).where('id', 1));
        expect(inserted, 1);
        expect(await db.table(probe).count(), 1);
        expect(await db.table(probe).value('label'), '?');
      } finally {
        await db.statement('drop table if exists $probe');
      }
    });

    test('paginate returns totals and pages', () async {
      final first = await query().orderBy('id').paginate(1, perPage: 2);
      expect(ids(first.data), [1, 2]);
      expect(first.total, 5);
      expect(first.lastPage, 3);
      expect(first.currentPage, 1);
      expect(first.hasMorePages, isTrue);
      expect(first.from, 1);
      expect(first.to, 2);

      final last = await query().orderBy('id').paginate(3, perPage: 2);
      expect(ids(last.data), [5]);
      expect(last.hasMorePages, isFalse);
      expect(last.from, 5);
      expect(last.to, 5);
      expect(await query().getCountForPagination(), 5);
    });

    test('simplePaginate reports whether more pages exist', () async {
      final first = await query().orderBy('id').simplePaginate(1, perPage: 2);
      expect(ids(first.data), [1, 2]);
      expect(first.hasMorePages, isTrue);

      final last = await query().orderBy('id').simplePaginate(3, perPage: 2);
      expect(ids(last.data), [5]);
      expect(last.hasMorePages, isFalse);
    });

    test('cursorPaginate returns a next cursor', () async {
      final first = await query().cursorPaginate(2);
      expect(ids(first.data), [1, 2]);
      expect(first.nextCursor?.parameters.values, [2]);
      expect(first.hasMorePages, isTrue);

      final second = await query().cursorPaginate(2, cursor: first.nextCursor);
      expect(ids(second.data), [3, 4]);
      expect(second.nextCursor?.parameters.values, [4]);
      expect(second.hasMorePages, isTrue);

      final third = await query().cursorPaginate(2, cursor: second.nextCursor);
      expect(ids(third.data), [5]);
      expect(third.nextCursor, isNull);
      expect(third.hasMorePages, isFalse);
    });

    test(
      'cursorPaginate groups existing OR conditions before the cursor',
      () async {
        final q = query().where('active', 1).orWhere('label', 'two');
        final sql = q.toSql();
        final bindings = q.getBindings();

        final first = await q.cursorPaginate(2);
        expect(ids(first.data), [1, 2]);
        expect(first.nextCursor?.parameters.values, [2]);
        expect(first.hasMorePages, isTrue);

        final second = await q.cursorPaginate(2, cursor: first.nextCursor);
        expect(ids(second.data), [3, 5]);
        expect(second.nextCursor, isNull);
        expect(second.hasMorePages, isFalse);
        expect(q.toSql(), sql);
        expect(q.getBindings(), bindings);
      },
    );

    for (final all in [false, true]) {
      test('cursorPaginate filters every UNION branch (all: $all)', () async {
        final q = query()
            .select(['id'])
            .where('active', 0)
            .union(query().select(['id']).where('active', 1), all: all);
        final sql = q.toSql();
        final bindings = q.getBindings();

        final first = await q.cursorPaginate(2);
        expect(ids(first.data), [1, 2]);
        expect(first.nextCursor?.parameters.values, [2]);
        expect(first.hasMorePages, isTrue);

        final second = await q.cursorPaginate(2, cursor: first.nextCursor);
        expect(ids(second.data), [3, 4]);
        expect(second.nextCursor?.parameters.values, [4]);
        expect(second.hasMorePages, isTrue);

        final third = await q.cursorPaginate(2, cursor: second.nextCursor);
        expect(ids(third.data), [5]);
        expect(third.nextCursor, isNull);
        expect(third.hasMorePages, isFalse);
        expect(q.toSql(), sql);
        expect(q.getBindings(), bindings);
      });
    }

    test('lazy and lazyById stream every row', () async {
      final lazyIds =
          await query().orderBy('id').lazy(2).map((row) => row['id']).toList();
      expect(lazyIds, [1, 2, 3, 4, 5]);

      final byId = await query().lazyById(2).map((row) => row['id']).toList();
      expect(byId, [1, 2, 3, 4, 5]);
    });

    test('eachById visits every row once', () async {
      final seen = <Object?>[];
      await query().eachById((row) async {
        seen.add(row['id']);
      }, count: 2);
      expect(seen, [1, 2, 3, 4, 5]);
    });

    test('cursor streams every row', () async {
      final ids =
          await query().orderBy('id').cursor().map((row) => row['id']).toList();
      expect(ids, [1, 2, 3, 4, 5]);
    });

    test('cursor supports bindings and cancellation', () async {
      final filtered =
          await query()
              .where('active', 1)
              .orderBy('id')
              .cursor()
              .map((row) => row['id'])
              .toList();
      expect(filtered, [1, 3, 5]);

      final firstTwo =
          await query()
              .orderBy('id')
              .cursor()
              .take(2)
              .map((row) => row['id'])
              .toList();
      expect(firstTwo, [1, 2]);
      expect(await query().count(), 5);
    });

    test('pagination validates page and sizes', () async {
      await expectLater(query().paginate(0), throwsA(isA<LaconicException>()));
      await expectLater(
        query().paginate(1, perPage: 0),
        throwsA(isA<LaconicException>()),
      );
      await expectLater(
        query().simplePaginate(0),
        throwsA(isA<LaconicException>()),
      );
      await expectLater(
        query().cursorPaginate(0),
        throwsA(isA<LaconicException>()),
      );
    });

    test('JSON contains, key and length conditions work', () async {
      expect(
        ids(
          await db
              .table(jsonTable)
              .whereJsonContains('tags', 'b')
              .orderBy('id')
              .get(),
        ),
        [1, 2],
      );
      expect(
        ids(
          await db.table(jsonTable).whereJsonDoesntContain('tags', 'b').get(),
        ),
        [3],
      );
      expect(
        await db
            .table(jsonTable)
            .whereJsonContainsKey('payload', r'$.name')
            .count(),
        3,
      );
      expect(
        await db
            .table(jsonTable)
            .whereJsonDoesntContainKey('payload', r'$.missing')
            .count(),
        3,
      );
      expect(
        ids(
          await db
              .table(jsonTable)
              .whereJsonLength('tags', 2)
              .orderBy('id')
              .get(),
        ),
        [1, 2],
      );
      expect(
        ids(
          await db
              .table(jsonTable)
              .whereJsonLength('tags', 1, comparator: '>')
              .orderBy('id')
              .get(),
        ),
        [1, 2],
      );
    });

    test('JSON paths and overlaps work', () async {
      expect(
        ids(
          await db
              .table(jsonTable)
              .whereJsonContains('payload->tags', 'b')
              .orderBy('id')
              .get(),
        ),
        [1, 2],
      );
      expect(
        ids(
          await db
              .table(jsonTable)
              .whereJsonLength('payload->tags', 2)
              .orderBy('id')
              .get(),
        ),
        [1, 2],
      );
      expect(
        await db.table(jsonTable).whereJsonContainsKey('payload->name').count(),
        3,
      );
      expect(
        ids(
          await db
              .table(jsonTable)
              .whereJsonOverlaps('tags', ['b'])
              .orderBy('id')
              .get(),
        ),
        [1, 2],
      );
      expect(
        ids(
          await db.table(jsonTable).whereJsonDoesntOverlap('tags', ['b']).get(),
        ),
        [3],
      );
    });

    test(
      'empty JSON overlaps retain path and surrounding binding semantics',
      () async {
        expect(
          await db
              .table(jsonTable)
              .whereJsonOverlaps('payload->tags', [])
              .count(),
          0,
        );
        expect(
          await db
              .table(jsonTable)
              .whereJsonDoesntOverlap('payload->tags', [])
              .count(),
          3,
        );
        expect(
          ids(
            await db
                .table(jsonTable)
                .where('id', 1)
                .orWhereJsonOverlaps('payload->tags', [])
                .where('id', 3)
                .get(),
          ),
          [1],
        );
        expect(
          ids(
            await db
                .table(jsonTable)
                .where('id', 1)
                .orWhereJsonDoesntOverlap('payload->tags', [])
                .where('id', 3)
                .orderBy('id')
                .get(),
          ),
          [1, 3],
        );
      },
    );

    test('groupLimit supports counts and a global row limit', () async {
      final q = db.table(groupLimitTable).groupLimit(1, 'grp').orderBy('val');
      expect(await q.count(), 2);
      expect(await q.count('val'), 2);
      expect((await q.clone().limit(1).get()).length, 1);
      expect(await q.clone().limit(0).get(), isEmpty);
      expect(
        await db
            .table(groupLimitTable)
            .groupLimit(2, 'grp')
            .orderBy('val')
            .offset(1)
            .count(),
        2,
      );
    });

    test(
      'groupLimit without explicit ordering selects one row per group',
      () async {
        final q = db.table(groupLimitTable).groupLimit(1, 'grp');
        expect(await q.count(), 2);
        expect((await q.get()).map((row) => row['grp']).toSet(), {'a', 'b'});
      },
    );

    test(
      'groupLimit cursor pagination preserves the partition selection',
      () async {
        final q = db
            .table('$groupLimitTable g')
            .select(['g.id', 'g.val'])
            .where('g.id', 0, comparator: '>')
            .groupLimit(1, 'g.grp')
            .orderByRaw('g.val + ? desc', [0]);
        final sql = q.toSql();
        final bindings = q.getBindings();
        final first = await q.cursorPaginate(1, column: 'g.id');
        expect(ids(first.data), [3]);
        expect(first.hasMorePages, isTrue);
        final second = await q.cursorPaginate(
          1,
          column: 'g.id',
          cursor: first.nextCursor,
        );
        expect(ids(second.data), [5]);
        expect(second.hasMorePages, isFalse);
        expect(
          (await q.cursorPaginate(1, column: 'g.id', cursor: 5)).data,
          isEmpty,
        );
        expect(q.toSql(), sql);
        expect(q.getBindings(), bindings);

        final skipped = db
            .table(groupLimitTable)
            .groupLimit(2, 'grp')
            .orderBy('val')
            .offset(1);
        final skippedFirst = await skipped.cursorPaginate(1);
        final skippedSecond = await skipped.cursorPaginate(
          1,
          cursor: skippedFirst.nextCursor,
        );
        expect(ids(skippedFirst.data) + ids(skippedSecond.data), [2, 5]);
      },
    );

    test('groupLimit keyset iteration pages the outer result', () async {
      final q = db
          .table('$groupLimitTable g')
          .groupLimit(1, 'g.grp')
          .orderByDesc('g.val');
      final chunks = <Object?>[];
      await q.chunkById(
        1,
        (rows) async => chunks.addAll(ids(rows)),
        column: 'g.id',
      );
      expect(chunks, [3, 5]);
      expect(await q.lazyById(1, 'g.id').map((row) => row['id']).toList(), [
        3,
        5,
      ]);
      final each = <Object?>[];
      await q.eachById(
        (row) async => each.add(row['id']),
        count: 1,
        column: 'g.id',
      );
      expect(each, [3, 5]);
      final skipped = db
          .table(groupLimitTable)
          .groupLimit(2, 'grp')
          .orderBy('val')
          .offset(1);
      expect(await skipped.lazyById(1).map((row) => row['id']).toList(), [
        2,
        5,
      ]);
    });

    test(
      'groupLimit pagination applies page offsets to the outer result',
      () async {
        final q = db
            .table(groupLimitTable)
            .select(['id', 'val'])
            .groupLimit(1, 'grp')
            .orderByRaw('val + ?', [0]);
        final sql = q.toSql();
        final bindings = q.getBindings();
        final first = await q.paginate(1, perPage: 1);
        final second = await q.paginate(2, perPage: 1);
        expect(first.total, 2);
        expect(first.lastPage, 2);
        expect(first.data.length, 1);
        expect(first.hasMorePages, isTrue);
        expect(second.total, 2);
        expect(second.data.length, 1);
        expect(second.hasMorePages, isFalse);
        expect((ids(first.data) + ids(second.data))..sort(), [1, 4]);
        expect((await q.paginate(3, perPage: 1)).data, isEmpty);

        final simpleFirst = await q.simplePaginate(1, perPage: 1);
        final simpleSecond = await q.simplePaginate(2, perPage: 1);
        expect(simpleFirst.data.length, 1);
        expect(simpleFirst.hasMorePages, isTrue);
        expect(simpleSecond.data.length, 1);
        expect(simpleSecond.hasMorePages, isFalse);
        expect((ids(simpleFirst.data) + ids(simpleSecond.data))..sort(), [
          1,
          4,
        ]);
        expect(q.toSql(), sql);
        expect(q.getBindings(), bindings);

        final skipped = db
            .table(groupLimitTable)
            .groupLimit(2, 'grp')
            .orderBy('val')
            .offset(1);
        final skippedPage = await skipped.paginate(1, perPage: 10);
        expect(skippedPage.total, 2);
        expect(ids(skippedPage.data)..sort(), [2, 5]);
      },
    );

    test('groupLimit limits rows per partition', () async {
      List<Object?> sortedIds(List<LaconicResult> rows) =>
          rows.map((row) => row['id']).toList()..sort();

      expect(
        sortedIds(
          await db
              .table(groupLimitTable)
              .groupLimit(2, 'grp')
              .orderBy('val')
              .get(),
        ),
        [1, 2, 4, 5],
      );

      expect(
        sortedIds(
          await db
              .table(groupLimitTable)
              .groupLimit(2, 'grp')
              .orderByDesc('val')
              .get(),
        ),
        [2, 3, 4, 5],
      );

      expect(
        sortedIds(
          await db
              .table(groupLimitTable)
              .groupLimit(2, 'grp')
              .orderBy('val')
              .offset(1)
              .get(),
        ),
        [2, 5],
      );

      final values =
          await db
                  .table(groupLimitTable)
                  .groupLimit(1, 'grp')
                  .orderBy('val')
                  .pluck('val')
              as List<Object?>;
      expect(values.map((value) => '$value').toList()..sort(), ['1', '10']);
    });

    test('insertOrIgnoreUsing ignores duplicate rows', () async {
      if (!supportsInsertOrIgnore) {
        await expectLater(
          query().insertOrIgnoreUsing([
            'id',
            'label',
          ], query().select(['id', 'label'])),
          throwsA(isA<LaconicException>()),
        );
        return;
      }
      const probe = 'laconic_insert_ignore_using_probe';
      await db.statement('drop table if exists $probe');
      await db.statement(
        'create table $probe (id int primary key, label varchar(20))',
      );
      try {
        final queryOne = query().select(['id', 'label']).where('id', 1);
        expect(
          await db.table(probe).insertOrIgnoreUsing(['id', 'label'], queryOne),
          1,
        );
        expect(
          await db.table(probe).insertOrIgnoreUsing(['id', 'label'], queryOne),
          0,
        );
        expect(await db.table(probe).count(), 1);
      } finally {
        await db.statement('drop table if exists $probe');
      }
    });
  }
}
