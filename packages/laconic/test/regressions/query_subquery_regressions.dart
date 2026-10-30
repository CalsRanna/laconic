import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class QuerySubqueryRegressions {
  static void register(Laconic Function() createDatabase) {
    group('Scalar subquery composition', () {
      const table = 'laconic_scalar_rows';
      const related = 'laconic_scalar_related';
      late Laconic db;
      QueryBuilder query() => db.table('$table u');
      QueryBuilder score([int extra = 0]) => db
          .table('$related r')
          .selectRaw('max(r.score) + ?', [extra])
          .whereColumn('r.parent_id', 'u.id')
          .where('r.label', 'skip', comparator: '!=');

      setUpAll(() async {
        db = createDatabase();
        await db.schema.dropIfExists(related);
        await db.schema.dropIfExists(table);
        await db.schema.create(table, (t) {
          t.integer('id').primary();
          t.integer('score').nullable();
          t.integer('other').nullable();
          t.string('label');
        });
        await db.schema.create(related, (t) {
          t.integer('parent_id');
          t.integer('score');
          t.string('label');
        });
        await db.table(table).insert([
          for (var id = 1; id <= 4; id++)
            {'id': id, 'score': 0, 'other': 0, 'label': 'initial'},
        ]);
        await db.table(related).insert(const [
          {'parent_id': 1, 'score': 10, 'label': 'old'},
          {'parent_id': 1, 'score': 30, 'label': 'current'},
          {'parent_id': 2, 'score': 20, 'label': 'current'},
          {'parent_id': 3, 'score': 40, 'label': 'current'},
          {'parent_id': 3, 'score': 90, 'label': 'skip'},
        ]);
      });
      setUp(() async {
        await db.table(table).update({
          'score': 0,
          'other': 0,
          'label': 'initial',
        });
      });
      tearDownAll(() async {
        try {
          await db.schema.dropIfExists(related);
          await db.schema.dropIfExists(table);
        } finally {
          await db.close();
        }
      });

      test('WHERE accepts a correlated builder on the left', () async {
        final q = query().where(score(), 30, comparator: '>=');
        expect(await q.orderBy('u.id').pluck('id'), [1, 3]);
      });

      test(
        'WHERE accepts a callback with subquery ordering and limit',
        () async {
          final q = query().where(
            (QueryBuilder sub) => sub
                .from('$related r')
                .select(['r.score'])
                .whereColumn('r.parent_id', 'u.id')
                .where('r.label', 'skip', comparator: '!=')
                .orderByDesc('r.score')
                .limit(1),
            30,
            comparator: '>=',
          );
          expect(await q.orderBy('u.id').pluck('id'), [1, 3]);
        },
      );

      test('WHERE callbacks compose with nested OR conditions', () async {
        final q = query().where('u.id', 1).orWhereNested((nested) {
          nested
              .where('u.id', 2, comparator: '>')
              .orWhere(
                (QueryBuilder sub) => sub
                    .from('$related r')
                    .selectRaw('max(r.score) + ?', [1])
                    .whereColumn('r.parent_id', 'u.id')
                    .where('r.label', 'skip', comparator: '!='),
                21,
              );
        });
        expect(await q.orderBy('u.id').pluck('id'), [1, 2, 3, 4]);
        expect(
          await query().where(score(), const Expression('25 + 5')).pluck('id'),
          [1],
        );
      });

      test('WHERE scalar NULL uses IS NULL and IS NOT NULL', () async {
        expect(await query().where(score(), null).pluck('id'), [4]);
        for (final comparator in ['!=', '<>']) {
          expect(
            await query()
                .where(score(), null, comparator: comparator)
                .orderBy('u.id')
                .pluck('id'),
            [1, 2, 3],
          );
        }
        expect(
          await query()
              .where('u.id', 2)
              .orWhere(score(), null)
              .orderBy('u.id')
              .pluck('id'),
          [2, 4],
        );
      });

      test('WHERE compares two bound scalar subqueries', () async {
        final right = db
            .table(related)
            .selectRaw('min(score) + ?', [15])
            .where('label', 'skip', comparator: '!=');
        expect(
          await query()
              .where(score(2), right, comparator: '>')
              .orderBy('u.id')
              .pluck('id'),
          [1, 3],
        );
      });

      test('ORDER BY accepts builders and descending callbacks', () async {
        expect(
          await query()
              .where('u.id', 4, comparator: '<')
              .orderBy(score(3))
              .offset(1)
              .limit(2)
              .pluck('id'),
          [1, 3],
        );
        expect(
          await query()
              .where('u.id', 4, comparator: '<')
              .orderByDesc(
                (QueryBuilder sub) => sub
                    .from('$related r')
                    .selectRaw('max(r.score) + ?', [4])
                    .whereColumn('r.parent_id', 'u.id')
                    .where('r.label', 'skip', comparator: '!='),
              )
              .pluck('id'),
          [3, 1, 2],
        );
      });

      test(
        'SELECT FROM WHERE and ORDER subqueries retain binding order',
        () async {
          final source = db.table(table).where('id', 0, comparator: '>');
          final projection = db
              .table(related)
              .selectRaw('max(score) + ?', [9])
              .where('parent_id', 1);
          final q = db
              .table(table)
              .fromSub(source, 'u')
              .select(['u.id'])
              .selectSub(projection, 'marker')
              .where('u.id', 4, comparator: '<')
              .where(score(1), 25, comparator: '>')
              .orderBy(score(2), direction: 'desc')
              .limit(1);
          final rows = await q.get();
          expect(rows.single['id'], 3);
          expect(rows.single['marker'], 39);
        },
      );

      test('composed WHERE and ORDER capture reusable subqueries', () async {
        final sub = score();
        final original = sub.toSql();
        final q = query().where(sub, 25, comparator: '>').orderByDesc(sub);
        final copy = q.clone();
        expect(sub.toSql(), original);
        sub.where('r.parent_id', 0);
        expect(await q.pluck('id'), [3, 1]);
        expect(await copy.pluck('id'), [3, 1]);
      });

      test(
        'UPDATE combines bound values and correlated scalar subqueries',
        () async {
          final sub = score(5);
          final original = sub.toSql();
          final values = <String, Object?>{
            'label': "updated' ?",
            'score': sub,
            'other':
                (QueryBuilder q) => q
                    .from('$related r')
                    .selectRaw('min(r.score) + ?', [7])
                    .whereColumn('r.parent_id', 'u.id')
                    .where('r.label', 'skip', comparator: '!='),
          };
          expect(
            await query().where('u.id', 4, comparator: '<').update(values),
            3,
          );
          final rows = await query().orderBy('u.id').get();
          expect(rows.map((r) => r['score']), [35, 25, 45, 0]);
          expect(rows.map((r) => r['other']), [17, 27, 47, 0]);
          expect(
            rows.take(3).map((r) => r['label']),
            everyElement("updated' ?"),
          );
          expect(rows.last['label'], 'initial');
          expect(values['score'], same(sub));
          expect(sub.toSql(), original);
        },
      );

      test('UPDATE stores NULL from an empty scalar subquery', () async {
        expect(
          await query().where('u.id', 4).update({
            'score':
                (QueryBuilder q) => q
                    .from('$related r')
                    .select(['r.score'])
                    .whereColumn('r.parent_id', 'u.id')
                    .where('r.label', 'missing'),
          }),
          1,
        );
        expect(await query().where('u.id', 4).value('score'), isNull);
      });

      test(
        'UPDATE binds assignment subqueries before left WHERE subqueries',
        () async {
          expect(
            await query()
                .where('u.id', 4, comparator: '<')
                .where(score(1), 25, comparator: '>')
                .update({'label': 'selected', 'other': score(11)}),
            2,
          );
          final rows =
              await query()
                  .where('u.id', 1)
                  .orWhere('u.id', 3)
                  .orderBy('u.id')
                  .get();
          expect(rows.map((r) => r['other']), [41, 51]);
          expect(rows.map((r) => r['label']), everyElement('selected'));
        },
      );

      test(
        'UPDATE with JOIN keeps join and scalar assignment bindings',
        () async {
          expect(
            await query()
                .join(
                  '$related j',
                  (join) =>
                      join.on('j.parent_id', 'u.id').where('j.label', 'old'),
                )
                .where('u.id', 1)
                .update({'u.label': 'joined', 'u.score': score(13)}),
            1,
          );
          final row = await query().where('u.id', 1).first();
          expect(row['score'], 43);
          expect(row['label'], 'joined');
        },
      );

      test('subquery operators and ordering directions are validated', () {
        expect(
          () => query().where(score(), 1, comparator: '= 1 or 1 ='),
          throwsA(isA<LaconicException>()),
        );
        expect(
          () => query().orderBy(score(), direction: 'desc; select 1'),
          throwsA(isA<LaconicException>()),
        );
      });

      test(
        'cursor pagination requires a named alias for subquery ordering',
        () async {
          await expectLater(
            query().orderBy(score()).cursorPaginate(2),
            throwsA(isA<LaconicException>()),
          );
        },
      );
    });
  }
}
