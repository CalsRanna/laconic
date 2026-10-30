import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class QueryResultRegressions {
  static void register(
    Laconic Function() createDatabase, {
    required bool supportsInsertOrIgnore,
    required int upsertUpdateCount,
  }) {
    group('query return values', () {
      const table = 'laconic_result_values';
      const target = 'laconic_result_target';
      late Laconic db;
      QueryBuilder query() => db.table(table);
      void define(Blueprint t) {
        t.integer('id').primary();
        t.integer('category').defaultTo(0);
        t.integer('amount').nullable();
        t.string('label').nullable();
        t.dateTime('recorded_at').nullable();
      }

      setUpAll(() async {
        db = createDatabase();
        await db.schema.dropIfExists(target);
        await db.schema.dropIfExists(table);
        await db.schema.create(table, define);
        await db.schema.create(target, define);
      });
      setUp(() async {
        await db.table(target).delete(allowWithoutWhere: true);
        await query().delete(allowWithoutWhere: true);
        await query().insert([
          {
            'id': 1,
            'category': 1,
            'amount': 10,
            'label': 'alpha',
            'recorded_at': '2026-01-01 08:00:00',
          },
          {
            'id': 2,
            'category': 1,
            'amount': 20,
            'label': 'zeta',
            'recorded_at': '2026-02-01 08:00:00',
          },
          {
            'id': 3,
            'category': 2,
            'amount': null,
            'label': null,
            'recorded_at': null,
          },
        ]);
      });
      tearDownAll(() async {
        try {
          await db.schema.dropIfExists(target);
          await db.schema.dropIfExists(table);
        } finally {
          await db.close();
        }
      });

      test(
        'min and max preserve text, numeric text, dates and numbers',
        () async {
          expect(await query().min('label'), 'alpha');
          expect(await query().max('label'), 'zeta');
          expect(await query().min('amount'), 10);
          expect(await query().max('amount'), 20);
          expect(
            await query().min('recorded_at'),
            await query().where('id', 1).value('recorded_at'),
          );
          expect(
            await query().max('recorded_at'),
            await query().where('id', 2).value('recorded_at'),
          );
          await query().where('id', 1).update({'label': '010'});
          await query().where('id', 2).update({'label': '2'});
          expect(await query().min('label'), '010');
          expect(await query().max('label'), '2');
        },
      );

      test(
        'aggregates distinguish empty and all-null results from zero',
        () async {
          for (final q in [query().where('id', 99), query().where('id', 3)]) {
            expect(await q.sum('amount'), 0);
            expect(await q.avg('amount'), isNull);
            expect(await q.min('amount'), isNull);
            expect(await q.max('amount'), isNull);
            expect(await q.min('label'), isNull);
            expect(await q.max('recorded_at'), isNull);
          }
          expect(await query().sum('amount'), 30);
          expect(await query().avg('amount'), 15.0);
          await query().where('id', 1).update({'amount': 0});
          expect(await query().where('id', 1).min('amount'), 0);
        },
      );

      test(
        'aggregate types survive unions and empty grouped results',
        () async {
          QueryBuilder union(bool empty) => query()
              .select(['id', 'label', 'amount', 'recorded_at'])
              .where('id', empty ? 98 : 1)
              .union(
                query()
                    .select(['id', 'label', 'amount', 'recorded_at'])
                    .where('id', empty ? 99 : 2),
              );
          expect(await union(false).max('label'), 'zeta');
          expect(await union(false).min('label'), 'alpha');
          expect(
            await union(false).max('recorded_at'),
            await query().where('id', 2).value('recorded_at'),
          );
          expect(await union(false).sum('amount'), 30);
          for (final q in [
            union(true),
            query().groupBy('category').havingRaw('sum(amount) > ?', [100]),
          ]) {
            expect(await q.sum('amount'), 0);
            expect(await q.avg('amount'), isNull);
            expect(await q.min('label'), isNull);
            expect(await q.max('recorded_at'), isNull);
          }
          expect(
            await query()
                .groupBy('category')
                .having('category', 1)
                .max('label'),
            'zeta',
          );
        },
      );

      test(
        'existence fallbacks are lazy and preserve callback results',
        () async {
          var calls = 0;
          Object? fallback() {
            calls++;
            return 'fallback';
          }

          expect(await query().existsOr(fallback), isTrue);
          expect(await query().where('id', 99).doesntExistOr(fallback), isTrue);
          expect(calls, 0);
          expect(await query().where('id', 99).existsOr(fallback), 'fallback');
          expect(await query().doesntExistOr(fallback), 'fallback');
          expect(calls, 2);
          expect(
            await query().where('id', 99).existsOr(() async => null),
            isNull,
          );
          expect(await query().doesntExistOr(() async => 42), 42);
          await expectLater(
            query().doesntExistOr(() => throw StateError('fallback')),
            throwsStateError,
          );
        },
      );

      test('subquery inserts report inserted rows including zero', () async {
        expect(
          await db.table(target).insertUsing([
            'id',
            'label',
          ], query().select(['id', 'label']).where('id', 3, comparator: '<')),
          2,
        );
        expect(
          await db.table(target).insertUsing([
            'id',
            'label',
          ], query().select(['id', 'label']).where('id', 99)),
          0,
        );
        expect(await db.table(target).count(), 2);
      });

      test('upserts return the database affected row count', () async {
        expect(
          await query().upsert(
            [
              {'id': 10, 'label': 'new'},
            ],
            uniqueBy: ['id'],
          ),
          1,
        );
        expect(
          await query().upsert(
            [
              {'id': 10, 'label': 'changed'},
            ],
            uniqueBy: ['id'],
            update: ['label'],
          ),
          upsertUpdateCount,
        );
        expect(await query().where('id', 10).value('label'), 'changed');
      });

      test('ignored inserts count only inserted rows', () async {
        if (!supportsInsertOrIgnore) {
          await expectLater(
            query().insertOrIgnore([
              {'id': 1},
            ]),
            throwsA(isA<LaconicException>()),
          );
          return;
        }
        expect(
          await query().insertOrIgnore([
            {'id': 1, 'label': 'ignored'},
            {'id': 10, 'label': 'new'},
          ]),
          1,
        );
        expect(
          await query().insertOrIgnore([
            {'id': 1},
          ]),
          0,
        );
        final source = query().select(['id', 'label']).whereIn('id', [1, 2]);
        expect(
          await db.table(target).insertOrIgnoreUsing(['id', 'label'], source),
          2,
        );
        expect(
          await db.table(target).insertOrIgnoreUsing(['id', 'label'], source),
          0,
        );
        expect(
          await db.table(target).insertOrIgnoreUsing([
            'id',
            'label',
          ], query().select(['id', 'label']).where('id', 99)),
          0,
        );
      });

      test(
        'updateOrInsert resolves values for each existence branch',
        () async {
          final observed = <bool>[];
          expect(
            await query().updateOrInsert({'id': 10}, (bool exists) {
              observed.add(exists);
              return {'label': exists ? 'updated' : 'created'};
            }),
            isTrue,
          );
          expect(await query().where('id', 10).value('label'), 'created');
          expect(
            await query().updateOrInsert({'id': 10}, (bool exists) async {
              observed.add(exists);
              return {'label': 'updated'};
            }),
            isTrue,
          );
          expect(observed, [false, true]);
          expect(await query().where('id', 10).value('label'), 'updated');
          expect(await query().updateOrInsert({'id': 10}), isTrue);
          expect(
            await query().updateOrInsert({'id': 10}, (bool exists) async {
              await query().where('id', 10).delete();
              return {'label': 'gone'};
            }),
            isFalse,
          );
        },
      );

      test(
        'declared empty-input and missing-record conventions stay intact',
        () async {
          expect(await query().where('id', 99).firstOrNull(), isNull);
          expect(await query().findOrNull(99), isNull);
          await expectLater(
            query().where('id', 99).first(),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(query().find(99), throwsA(isA<LaconicException>()));
          await expectLater(
            query().insert([]),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            query().insertOrIgnore([]),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            query().upsert([], uniqueBy: ['id']),
            throwsA(isA<LaconicException>()),
          );
        },
      );
    });
  }
}
