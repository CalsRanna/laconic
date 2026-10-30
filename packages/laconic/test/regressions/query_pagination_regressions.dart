import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class QueryPaginationRegressions {
  static const rows = [
    {'id': 1, 'bucket': 1, 'score': 10, 'label': 'a'},
    {'id': 2, 'bucket': 1, 'score': 30, 'label': 'b'},
    {'id': 3, 'bucket': 1, 'score': 30, 'label': 'c'},
    {'id': 4, 'bucket': 2, 'score': 10, 'label': 'd'},
    {'id': 5, 'bucket': 2, 'score': 20, 'label': 'e'},
    {'id': 6, 'bucket': 2, 'score': 20, 'label': 'f'},
    {'id': 7, 'bucket': 3, 'score': 10, 'label': 'g'},
  ];

  static void register(Laconic Function() createDatabase) {
    group('bidirectional cursor pagination', () {
      const table = 'laconic_cursor_values';
      late Laconic db;
      QueryBuilder query() => db.table(table);
      setUpAll(() async {
        db = createDatabase();
        await db.schema.dropIfExists(table);
        await db.schema.create(table, (t) {
          t.integer('id').primary();
          t.integer('bucket');
          t.integer('score');
          t.string('label').nullable();
        });
        await query().insert(rows);
      });
      tearDownAll(() async {
        try {
          await db.schema.dropIfExists(table);
        } finally {
          await db.close();
        }
      });

      Future<void> traverse(
        QueryBuilder q,
        List<Object?> expected, {
        int perPage = 2,
        String resultKey = 'id',
      }) async {
        final sql = q.toSql();
        final bindings = q.getBindings();
        final forward = <List<Object?>>[];
        LaconicCursor? cursor;
        late LaconicCursorPage page;
        do {
          page = await q.cursorPaginate(perPage, cursor: cursor);
          forward.add([for (final row in page.data) row[resultKey]]);
          expect(page.hasPreviousPages, forward.length > 1);
          expect(page.hasMorePages, page.nextCursor != null);
          cursor = page.nextCursor;
          expect(forward.length, lessThanOrEqualTo(expected.length + 1));
        } while (cursor != null);
        expect(forward.expand((items) => items).toList(), expected);
        for (var i = forward.length - 2; i >= 0; i--) {
          expect(page.previousCursor?.pointsToNextItems, isFalse);
          page = await q.cursorPaginate(perPage, cursor: page.previousCursor);
          expect([for (final row in page.data) row[resultKey]], forward[i]);
          expect(page.hasMorePages, isTrue);
          expect(page.hasPreviousPages, i > 0);
        }
        expect(page.previousCursor, isNull);
        if (forward.length > 1) {
          final next = await q.cursorPaginate(perPage, cursor: page.nextCursor);
          expect([for (final row in next.data) row[resultKey]], forward[1]);
        }
        expect(q.toSql(), sql);
        expect(q.getBindings(), bindings);
      }

      for (final size in [1, 2, 3, 7, 10]) {
        test(
          'single-column ascending and descending pages, size $size',
          () async {
            await traverse(query(), [1, 2, 3, 4, 5, 6, 7], perPage: size);
            await traverse(query().orderByDesc('id'), [
              7,
              6,
              5,
              4,
              3,
              2,
              1,
            ], perPage: size);
          },
        );
        test(
          'mixed composite ordering crosses ties in both directions, size $size',
          () async {
            await traverse(
              query().orderBy('bucket').orderByDesc('score').orderBy('id'),
              [2, 3, 1, 5, 6, 4, 7],
              perPage: size,
            );
          },
        );
      }

      test('composite boundaries contain every ordering value', () async {
        final q = query().orderBy('bucket').orderByDesc('score').orderBy('id');
        final first = await q.cursorPaginate(2);
        expect(first.nextCursor!.parameters, {
          'bucket': 1,
          'score': 30,
          'id': 3,
        });
        expect(first.nextCursor!.pointsToNextItems, isTrue);
        final second = await q.cursorPaginate(2, cursor: first.nextCursor);
        expect(second.previousCursor!.parameters, {
          'bucket': 1,
          'score': 10,
          'id': 1,
        });
        expect(
          () => second.previousCursor!.parameters['id'] = 99,
          throwsUnsupportedError,
        );
      });

      test(
        'scalar cursors preserve legacy calls and obey descending order',
        () async {
          expect(
            (await query().cursorPaginate(
              2,
              cursor: 2,
            )).data.map((row) => row['id']),
            [3, 4],
          );
          expect(
            (await query()
                .orderByDesc('id')
                .cursorPaginate(2, cursor: 6)).data.map((row) => row['id']),
            [5, 4],
          );
        },
      );

      test(
        'existing OR filters are grouped before the composite boundary',
        () async {
          await traverse(
            query()
                .where('bucket', 1)
                .orWhere('score', 20)
                .orderBy('bucket')
                .orderByDesc('score')
                .orderBy('id'),
            [2, 3, 1, 5, 6],
          );
        },
      );

      test(
        'qualified columns, projection aliases and selected expressions work',
        () async {
          await traverse(
            db
                .table('$table t')
                .select(['t.id as row_id', 't.bucket as category', 't.score'])
                .orderBy('t.bucket')
                .orderByDesc('t.score')
                .orderBy('t.id'),
            [2, 3, 1, 5, 6, 4, 7],
            resultKey: 'row_id',
          );
          await traverse(
            query()
                .select(['id as row_id', 'bucket as category', 'score'])
                .orderBy('category')
                .orderByDesc('score')
                .orderBy('row_id'),
            [2, 3, 1, 5, 6, 4, 7],
            resultKey: 'row_id',
          );
          await traverse(
            query()
                .select(['id'])
                .selectRaw('score + ? as sort_score', [5])
                .whereRaw('score >= ?', [10])
                .orderByDesc('sort_score')
                .orderBy('id'),
            [2, 3, 5, 6, 1, 4, 7],
          );
        },
      );

      for (final all in [false, true]) {
        test(
          'composite union pagination filters the complete union, all $all',
          () async {
            await traverse(
              query()
                  .select(['id', 'bucket', 'score'])
                  .where('bucket', 1)
                  .union(
                    query()
                        .select(['id', 'bucket', 'score'])
                        .where('bucket', 1, comparator: '>'),
                    all: all,
                  )
                  .orderBy('bucket')
                  .orderByDesc('score')
                  .orderBy('id'),
              [2, 3, 1, 5, 6, 4, 7],
            );
          },
        );
      }

      test(
        'grouped and distinct results are filtered after aggregation',
        () async {
          await traverse(
            query()
                .select(['bucket'])
                .selectRaw('sum(score) as total')
                .groupBy('bucket')
                .havingRaw('sum(score) >= ?', [10])
                .orderByDesc('total')
                .orderBy('bucket'),
            [1, 2, 3],
            perPage: 1,
            resultKey: 'bucket',
          );
          await traverse(
            query().select(['bucket']).distinct().orderByDesc('bucket'),
            [3, 2, 1],
            perPage: 1,
            resultKey: 'bucket',
          );
        },
      );

      test(
        'group-limited results retain partition selection when moving back',
        () async {
          final q = query()
              .select(['id', 'bucket', 'score'])
              .groupLimit(1, 'bucket')
              .orderByDesc('score')
              .orderBy('id');
          final first = await q.cursorPaginate(2);
          expect(first.data.map((row) => row['id']), [2, 5]);
          final second = await q.cursorPaginate(2, cursor: first.nextCursor);
          expect(second.data.map((row) => row['id']), [7]);
          final previous = await q.cursorPaginate(
            2,
            cursor: second.previousCursor,
          );
          expect(previous.data.map((row) => row['id']), [2, 5]);
          expect(previous.previousCursor, isNull);
        },
      );

      test('empty pages have no navigation cursors', () async {
        for (final cursor in [
          null,
          LaconicCursor({'id': 100}),
          LaconicCursor({'id': 0}, pointsToNextItems: false),
        ]) {
          final page = await query()
              .where('id', -1)
              .cursorPaginate(2, cursor: cursor);
          expect(page.data, isEmpty);
          expect(page.nextCursor, isNull);
          expect(page.previousCursor, isNull);
          expect(page.hasMorePages, isFalse);
          expect(page.hasPreviousPages, isFalse);
        }
      });

      test(
        'invalid boundaries and unsupported orderings fail explicitly',
        () async {
          final q = query().orderBy('bucket').orderBy('id');
          for (final cursor in [
            2,
            LaconicCursor({'bucket': 1}),
            LaconicCursor({'bucket': 1, 'id': null}),
            LaconicCursor({'bucket': 1, 'id': 2, 'score': 30}),
          ]) {
            await expectLater(
              q.cursorPaginate(2, cursor: cursor),
              throwsA(isA<LaconicException>()),
            );
          }
          await expectLater(
            query().orderByRaw('id desc').cursorPaginate(2),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            query().select(['label']).orderBy('id').cursorPaginate(20),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            query().orderBy('id', direction: 'wrong').cursorPaginate(2),
            throwsA(isA<LaconicException>()),
          );
          await query().where('id', 7).update({'label': null});
          try {
            await expectLater(
              query().orderBy('label').orderBy('id').cursorPaginate(20),
              throwsA(isA<LaconicException>()),
            );
          } finally {
            await query().where('id', 7).update({'label': 'g'});
          }
        },
      );
    });
  }
}
