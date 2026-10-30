import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class QueryConvenienceRegressions {
  static void register(Laconic Function() createDatabase) {
    group('Query convenience APIs', () {
      const table = 'laconic_convenience_rows';
      late Laconic db;
      final now = DateTime.utc(2026, 10, 30, 12, 34, 56, 789, 123);
      QueryBuilder query() => db.table(table);
      List<Object?> ids(List<LaconicResult> rows, [String column = 'id']) =>
          rows.map((row) => row[column]).toList();

      setUpAll(() async {
        db = createDatabase();
        await db.schema.dropIfExists(table);
        await db.schema.create(table, (t) {
          t.integer('id');
          t.primary(['id']);
          t.integer('bucket');
          t.integer('val');
          t.string('label');
          t.dateTime('due_at').nullable();
          t.dateTime('review_at').nullable();
        });
        const dates = [
          '2026-10-29 23:59:59',
          '2026-10-30 00:00:00',
          '2026-10-30 12:34:56',
          '2026-10-30 23:59:59',
          '2026-10-31 00:00:00',
          null,
        ];
        const reviews = [4, 0, 2, 1, 4, 5];
        await query().insert([
          for (var i = 0; i < dates.length; i++)
            {
              'id': i + 1,
              'bucket': (i + 1) % 2,
              'val': (i + 1) * 10,
              'label': 'row ${i + 1}',
              'due_at': dates[i],
              'review_at': dates[reviews[i]],
            },
        ]);
      });
      tearDownAll(() async {
        try {
          await db.schema.dropIfExists(table);
        } finally {
          await db.close();
        }
      });

      final dateCases = <
        ({
          String name,
          QueryBuilder Function(QueryBuilder) and,
          QueryBuilder Function(QueryBuilder) or,
          List<int> ids,
        })
      >[
        (
          name: 'past',
          and: (q) => q.wherePast('due_at', now: now),
          or: (q) => q.orWherePast('due_at', now: now),
          ids: [1, 2],
        ),
        (
          name: 'now or past',
          and: (q) => q.whereNowOrPast('due_at', now: now),
          or: (q) => q.orWhereNowOrPast('due_at', now: now),
          ids: [1, 2, 3],
        ),
        (
          name: 'future',
          and: (q) => q.whereFuture('due_at', now: now),
          or: (q) => q.orWhereFuture('due_at', now: now),
          ids: [4, 5],
        ),
        (
          name: 'now or future',
          and: (q) => q.whereNowOrFuture('due_at', now: now),
          or: (q) => q.orWhereNowOrFuture('due_at', now: now),
          ids: [3, 4, 5],
        ),
        (
          name: 'today',
          and: (q) => q.whereToday('due_at', now: now),
          or: (q) => q.orWhereToday('due_at', now: now),
          ids: [2, 3, 4],
        ),
        (
          name: 'before today',
          and: (q) => q.whereBeforeToday('due_at', now: now),
          or: (q) => q.orWhereBeforeToday('due_at', now: now),
          ids: [1],
        ),
        (
          name: 'today or before',
          and: (q) => q.whereTodayOrBefore('due_at', now: now),
          or: (q) => q.orWhereTodayOrBefore('due_at', now: now),
          ids: [1, 2, 3, 4],
        ),
        (
          name: 'after today',
          and: (q) => q.whereAfterToday('due_at', now: now),
          or: (q) => q.orWhereAfterToday('due_at', now: now),
          ids: [5],
        ),
        (
          name: 'today or after',
          and: (q) => q.whereTodayOrAfter('due_at', now: now),
          or: (q) => q.orWhereTodayOrAfter('due_at', now: now),
          ids: [2, 3, 4, 5],
        ),
      ];
      for (final c in dateCases) {
        test(
          'relative date ${c.name} handles boundaries, NULL and OR',
          () async {
            expect(ids(await c.and(query()).orderBy('id').get()), c.ids);
            expect(
              ids(
                await c
                    .and(query().where('id', 1, comparator: '>'))
                    .orderBy('id')
                    .get(),
              ),
              c.ids.where((id) => id > 1),
            );
            expect(
              ids(await c.or(query().where('id', 6)).orderBy('id').get()),
              [...c.ids, 6],
            );
          },
        );
      }

      test(
        'date lists share a bound clock and preserve explicit boolean grouping',
        () async {
          final q = query().wherePast(['due_at', 'review_at'], now: now);
          expect(q.getBindings(), [
            '2026-10-30 12:34:56',
            '2026-10-30 12:34:56',
          ]);
          expect(ids(await q.orderBy('id').get()), [2]);
          expect(
            ids(
              await query()
                  .where('id', 0)
                  .orWherePast(['due_at', 'review_at'], now: now)
                  .orderBy('id')
                  .get(),
            ),
            [1, 2, 4],
          );
          expect(
            ids(
              await query()
                  .where('id', 1, comparator: '>')
                  .whereNested(
                    (q) => q.orWherePast(['due_at', 'review_at'], now: now),
                  )
                  .orderBy('id')
                  .get(),
            ),
            [2, 4],
          );
          expect(
            ids(
              await query()
                  .whereToday(['due_at', 'review_at'], now: now)
                  .orderBy('id')
                  .get(),
            ),
            [3, 4],
          );
          final before = q.toSql();
          final bindings = q.getBindings();
          expect(() => q.wherePast([1, 2]), throwsA(isA<LaconicException>()));
          expect(q.toSql(), before);
          expect(q.getBindings(), bindings);
          expect(query().whereToday([]).getBindings(), isEmpty);
          await expectLater(
            query().wherePast([]).delete(),
            throwsA(isA<LaconicException>()),
          );
        },
      );

      test(
        'date helpers use the application clock and remain usable in writes',
        () async {
          final before = DateTime.now();
          final q = query().wherePast(['due_at', 'review_at']);
          final after = DateTime.now();
          final bindings = q.getBindings();
          expect(bindings.first, bindings.last);
          final captured = DateTime.parse(bindings.first as String);
          final start = DateTime(
            before.year,
            before.month,
            before.day,
            before.hour,
            before.minute,
            before.second,
          );
          expect(captured.isBefore(start), isFalse);
          expect(captured.isAfter(after), isFalse);
          try {
            expect(
              await query().wherePast('due_at', now: now).increment('val'),
              2,
            );
            expect(await query().where('id', 1).value('val'), 11);
            expect(await query().where('id', 3).value('val'), 30);
          } finally {
            await query().wherePast('due_at', now: now).decrement('val');
          }
        },
      );

      test(
        'descending chunks replace ordering, group OR, bound offset/limit and protect cursor snapshots',
        () async {
          final q = query()
              .where('bucket', 0)
              .orWhere('bucket', 1)
              .orderByRaw('id + ?', [0])
              .offset(1)
              .limit(3);
          final sql = q.toSql();
          final bindings = q.getBindings();
          final seen = <Object?>[];
          final pages = <int>[];
          expect(
            await q.chunkByIdDesc(2, (
              List<LaconicResult> rows,
              int page,
            ) async {
              seen.addAll(ids(rows));
              pages.add(page);
              rows.last.values[0] = -100;
              rows.clear();
            }),
            isTrue,
          );
          expect(seen, [5, 4, 3]);
          expect(pages, [1, 2]);
          expect(q.toSql(), sql);
          expect(q.getBindings(), bindings);
          for (final descending in [false, true]) {
            final ordered = <Object?>[];
            await q.orderedChunkById(
              2,
              (List<LaconicResult> rows) => ordered.addAll(ids(rows)),
              descending: descending,
            );
            expect(ordered, descending ? [5, 4, 3] : [2, 3, 4]);
          }
        },
      );

      test(
        'lazy descending keys support qualified columns and selected aliases',
        () async {
          final q = db
              .table('$table t')
              .select(['t.id as cursor_id', 't.label'])
              .offset(1)
              .limit(4);
          final sql = q.toSql();
          expect(
            await q
                .lazyByIdDesc(2, 't.id', 'cursor_id')
                .map((r) => r['cursor_id'])
                .toList(),
            [5, 4, 3, 2],
          );
          expect(q.toSql(), sql);
          final seen = <Object?>[];
          await q.chunkByIdDesc(
            2,
            (List<LaconicResult> rows) => seen.addAll(ids(rows, 'cursor_id')),
            column: 't.id',
            alias: 'cursor_id',
          );
          expect(seen, [5, 4, 3, 2]);
        },
      );

      test(
        'descending chunks apply the boundary outside UNION and groupLimit',
        () async {
          final q = query()
              .select(['id as cursor_id', 'bucket'])
              .where('bucket', 1)
              .union(
                (q) => q
                    .from(table)
                    .select(['id as cursor_id', 'bucket'])
                    .where('bucket', 0),
              )
              .offset(1)
              .limit(5);
          final sql = q.toSql();
          final bindings = q.getBindings();
          final seen = <Object?>[];
          await q.chunkByIdDesc(
            2,
            (List<LaconicResult> rows) => seen.addAll(ids(rows, 'cursor_id')),
            alias: 'cursor_id',
          );
          expect(seen, [5, 4, 3, 2, 1]);
          expect(q.toSql(), sql);
          expect(q.getBindings(), bindings);
          expect(
            await q
                .lazyByIdDesc(2, 'id', 'cursor_id')
                .map((r) => r['cursor_id'])
                .toList(),
            seen,
          );
          final grouped = db
              .table('$table t')
              .groupLimit(1, 't.bucket')
              .orderByRaw('val + ?', [0]);
          final groupedSql = grouped.toSql();
          expect(
            await grouped.lazyByIdDesc(1, 't.id').map((r) => r['id']).toList(),
            [2, 1],
          );
          expect(grouped.toSql(), groupedSql);
          expect(grouped.getBindings(), [0, 1]);
        },
      );

      test(
        'descending chunks stop promptly for false, errors and cancelled streams',
        () async {
          expect(
            await query().chunkByIdDesc(
              2,
              (List<LaconicResult> rows) async => false,
            ),
            isFalse,
          );
          expect(
            await query().lazyByIdDesc(2).take(1).map((r) => r['id']).toList(),
            [6],
          );
          await expectLater(
            query().orderedChunkById(
              2,
              (List<LaconicResult> rows) => throw StateError('callback failed'),
              descending: true,
            ),
            throwsStateError,
          );
          var called = false;
          expect(
            await query().limit(0).chunkByIdDesc(2, (_) {
              called = true;
            }),
            isTrue,
          );
          expect(called, isFalse);
          expect(
            await query().where('id', 999).chunkByIdDesc(2, (_) {
              called = true;
            }),
            isTrue,
          );
          expect(called, isFalse);
        },
      );

      test(
        'descending chunks reject invalid sizes and absent or null cursors',
        () async {
          await expectLater(
            query().chunkByIdDesc(0, (_) {}),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            query().orderedChunkById(-1, (_) {}),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            query().lazyByIdDesc(0).toList(),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            query().select(['label']).chunkByIdDesc(2, (_) {}),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            query()
                .selectRaw('null as cursor_id')
                .lazyByIdDesc(2, 'id', 'cursor_id')
                .toList(),
            throwsA(isA<LaconicException>()),
          );
        },
      );

      test(
        'descending key iteration visits records once while callbacks remove visited rows',
        () async {
          final seen = <Object?>[];
          try {
            await query().where('val', 0, comparator: '>').chunkByIdDesc(2, (
              List<LaconicResult> rows,
            ) async {
              seen.addAll(ids(rows));
              await query().whereIn('id', ids(rows)).update({'val': 0});
            });
            expect(seen, [6, 5, 4, 3, 2, 1]);
          } finally {
            for (var id = 1; id <= 6; id++) {
              await query().where('id', id).update({'val': id * 10});
            }
          }
        },
      );

      test(
        'chunkMap awaits mappings in order, retains null/false and preserves bounds',
        () async {
          final q = query().orderByDesc('id').offset(1).limit(3);
          final sql = q.toSql();
          final bindings = q.getBindings();
          final visits = <Object?>[];
          final List<int> mapped = await q.chunkMap<int>((row) async {
            await Future<void>.delayed(Duration.zero);
            visits.add(row['id']);
            return (row['id'] as int) * 2;
          }, count: 2);
          expect(mapped, [10, 8, 6]);
          expect(visits, [5, 4, 3]);
          expect(q.toSql(), sql);
          expect(q.getBindings(), bindings);
          expect(
            await q.chunkMap<Object?>(
              (row) =>
                  row['id'] == 5
                      ? null
                      : row['id'] == 4
                      ? false
                      : 0,
              count: 1,
            ),
            [null, false, 0],
          );
          expect(
            await query()
                .where('id', 999)
                .orderBy('id')
                .chunkMap<int>((_) => 1),
            isEmpty,
          );
          await expectLater(
            query().chunkMap<int>((_) => 1),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            q.chunkMap<int>((_) => 1, count: 0),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            q.chunkMap<int>(
              (_) async => throw StateError('mapper failed'),
              count: 2,
            ),
            throwsStateError,
          );
        },
      );

      test(
        'tap composes constraints and pipe preserves results, futures and null fallback',
        () async {
          final original = query();
          var calls = 0;
          final q = original.clone();
          expect(
            q.tap((q) {
              calls++;
              q.where('bucket', 1);
              return query();
            }),
            same(q),
          );
          expect(calls, 1);
          expect(await q.count(), 3);
          expect(await original.count(), 6);
          expect(q.pipe((q) => q.where('id', 3)), same(q));
          final Future<int> count = q.pipe((q) => q.count());
          expect(await count, 1);
          expect(q.pipe((_) => false), isFalse);
          expect(q.pipe((_) => 0), 0);
          expect(q.pipe((_) => null), same(q));
          void constrain(QueryBuilder query) {
            query.where('val', 30);
          }

          expect(q.pipe(constrain), same(q));
          final future = Future<int>.value(7);
          expect(q.pipe((_) => future), same(future));
          expect(await q.pipe((_) async => null), isNull);
          expect(() => q.tap((_) => throw StateError('tap')), throwsStateError);
          expect(
            () => q.pipe((_) => throw StateError('pipe')),
            throwsStateError,
          );
          await expectLater(
            query().tap((_) {}).delete(),
            throwsA(isA<LaconicException>()),
          );
        },
      );

      test(
        'rawValue binds expressions, preserves scalar types and does not replace stored projections',
        () async {
          final q = query()
              .selectRaw('? as ignored', [999])
              .where('id', 2)
              .orderBy('id');
          final sql = q.toSql();
          final bindings = q.getBindings();
          expect(await q.rawValue('val + ?', [7]), 27);
          expect(await q.rawValue('label'), 'row 2');
          expect(await q.rawValue('null'), isNull);
          expect(q.toSql(), sql);
          expect(q.getBindings(), bindings);
          expect(
            await query().where('id', 999).rawValue('val + ?', [7]),
            isNull,
          );
          final aggregate = await query()
              .where('id', 2, comparator: '<=')
              .rawValue('sum(val) + ?', [1]);
          final native =
              (await db.select(
                'select sum(val) + ? as total from $table where id <= ?',
                [1, 2],
              )).single['total'];
          // MySQL DECIMAL text can retain its native scale; never coerce it.
          expect(aggregate.runtimeType, native.runtimeType);
          expect(num.parse('$aggregate'), 31);
          expect(await query().orderByDesc('id').offset(1).rawValue('val'), 50);
        },
      );

      test(
        'rawValue handles complete UNION and groupLimit results with correct binding order',
        () async {
          final q = query()
              .selectRaw('id + ? as cursor_id', [0])
              .where('id', 999)
              .union(
                (q) => q
                    .from(table)
                    .selectRaw('id + ? as cursor_id', [0])
                    .where('id', 1, comparator: '>'),
              )
              .orderByDesc('cursor_id')
              .offset(1);
          final sql = q.toSql();
          final bindings = q.getBindings();
          expect(await q.rawValue('cursor_id + ?', [100]), 105);
          expect(q.toSql(), sql);
          expect(q.getBindings(), bindings);
          expect(
            await query()
                .where('bucket', 0)
                .groupLimit(1, 'bucket')
                .orderByDesc('val')
                .rawValue('id + ?', [10]),
            16,
          );
        },
      );

      test('JOIN EXISTS variants also accept existing query builders', () async {
        final sub = db
            .table('$table i')
            .whereColumn('i.id', 'o.id')
            .where('i.bucket', 0);
        QueryBuilder joined(void Function(JoinClause) condition) => db
            .table('$table o')
            .select(['o.id'])
            .join('$table j', (join) {
              join.on('o.id', 'j.id');
              condition(join);
            })
            .orderBy('o.id');
        expect(ids(await joined((j) => j.whereExists(sub)).get()), [2, 4, 6]);
        expect(ids(await joined((j) => j.whereNotExists(sub)).get()), [
          1,
          3,
          5,
        ]);
        // Group the OR predicates so the key equality continues to constrain the join.
        expect(
          ids(
            await joined(
              (j) => j.whereNested(
                (nested) => nested.where('o.id', 1).orWhereExists(sub),
              ),
            ).get(),
          ),
          [1, 2, 4, 6],
        );
        expect(
          ids(
            await joined(
              (j) => j.whereNested(
                (nested) => nested.where('o.id', 2).orWhereNotExists(sub),
              ),
            ).get(),
          ),
          [1, 2, 3, 5],
        );
      });

      test(
        'EXISTS variants accept builders, preserve correlation and snapshot SQL/bindings',
        () async {
          QueryBuilder subquery() => db
              .table('$table i')
              .selectRaw('?', [99])
              .whereColumn('i.bucket', 'o.bucket')
              .where('i.id', 4)
              .orderByRaw('?', [10])
              .limit(1);
          final sub = subquery();
          final sql = sub.toSql();
          final bindings = sub.getBindings();
          final outer = db
              .table('$table o')
              .where('o.id', 2, comparator: '>')
              .whereExists(sub)
              .orderBy('o.id');
          expect(sub.toSql(), sql);
          expect(sub.getBindings(), bindings);
          expect(outer.getBindings(), containsAllInOrder([2, 99, 4]));
          expect(outer.getBindings(), isNot(contains(10)));
          sub.where('i.id', 0);
          expect(ids(await outer.get()), [4, 6]);
          expect(
            ids(
              await db
                  .table('$table o')
                  .where('o.id', 2, comparator: '>')
                  .whereNotExists(subquery())
                  .orderBy('o.id')
                  .get(),
            ),
            [3, 5],
          );
          expect(
            ids(
              await db
                  .table('$table o')
                  .where('o.id', 1)
                  .orWhereExists(subquery())
                  .orderBy('o.id')
                  .get(),
            ),
            [1, 2, 4, 6],
          );
          expect(
            ids(
              await db
                  .table('$table o')
                  .where('o.id', 1)
                  .orWhereNotExists(subquery())
                  .orderBy('o.id')
                  .get(),
            ),
            [1, 3, 5],
          );
          expect(await query().whereExists(query().limit(0)).get(), isEmpty);
          final grouped = query()
              .select(['bucket'])
              .groupBy('bucket')
              .havingRaw('count(*) > ?', [2]);
          expect(await query().whereExists(grouped).count(), 6);
          final invalid = query();
          final before = invalid.toSql();
          expect(
            () => invalid.whereExists('select 1'),
            throwsA(isA<LaconicException>()),
          );
          expect(invalid.toSql(), before);
        },
      );
    });
  }
}
