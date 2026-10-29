import 'dart:convert';

import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class QuerySemanticsRegressions {
  static void register(
    Laconic Function() createDatabase, {
    bool supportsOrderedWrites = true,
    bool supportsWriteOffset = false,
    bool supportsLimitedJoinWrites = true,
  }) {
    group('Laravel query semantics', () {
      const table = 'laconic_semantics';
      const related = 'laconic_semantics_related';
      late Laconic db;
      QueryBuilder query() => db.table(table);

      setUp(() async {
        db = createDatabase();
        await db.schema.dropIfExists(related);
        await db.schema.dropIfExists(table);
        await db.schema.create(table, (t) {
          t.integer('id').primary();
          t.integer('group');
          t.string('key');
          t.string('odd"name]').nullable();
          t.json('payload');
        });
        await db.schema.create(related, (t) {
          t.integer('parent_id');
          t.string('label');
        });
        await query().insert([
          for (var i = 1; i <= 5; i++)
            {
              'id': i,
              'group': i,
              'key': 'row-$i',
              'payload': jsonEncode({
                'enabled': i.isOdd,
                'name': 'name-$i',
                'count': i,
                'nested': {'value': i},
                'a.b': i,
                'a->b': i,
                'items': [i, i + 1],
              }),
            },
        ]);
        await db.table(related).insert([
          {'parent_id': 2, 'label': 'match'},
          {'parent_id': 4, 'label': 'other'},
        ]);
      });
      tearDown(() async {
        try {
          await db.schema.dropIfExists(related);
          await db.schema.dropIfExists(table);
        } finally {
          await db.close();
        }
      });

      test(
        'ordered and offset writes are applied or explicitly rejected',
        () async {
          final ordered = query()
              .where('id', 0, comparator: '>')
              .orderByDesc('id')
              .limit(1);
          if (supportsOrderedWrites) {
            expect(await ordered.increment('group', amount: 10), 1);
            expect(await query().where('id', 5).value('group'), 15);
            expect(await ordered.decrementEach({'group': 2}), 1);
            expect(await query().where('id', 5).value('group'), 13);
            expect(await ordered.delete(), 1);
            expect(await query().where('id', 5).exists(), isFalse);
          } else {
            await expectLater(
              ordered.update({'key': 'wrong'}),
              throwsA(isA<LaconicException>()),
            );
            await expectLater(
              ordered.delete(),
              throwsA(isA<LaconicException>()),
            );
            expect(await query().count(), 5);
          }
          final offset = query()
              .where('id', 0, comparator: '>')
              .orderBy('id')
              .offset(1)
              .limit(1);
          if (supportsWriteOffset) {
            expect(await offset.update({'key': 'offset'}), 1);
            expect(await query().where('key', 'offset').pluck('id'), [2]);
          } else {
            await expectLater(
              offset.update({'key': 'offset'}),
              throwsA(isA<LaconicException>()),
            );
            expect(await query().where('key', 'offset').count(), 0);
          }
        },
      );

      test('derived joins keep binding order in limited writes', () async {
        QueryBuilder joined() => db
            .table('$table as target')
            .joinSub(
              db.table(related).select(['parent_id']).where('label', 'match'),
              'source',
              'target.id',
              '=',
              'source.parent_id',
            )
            .where('target.id', 1, comparator: '>')
            .limit(1);
        if (supportsLimitedJoinWrites) {
          expect(await joined().update({'target.key': 'derived'}), 1);
          expect(await query().where('key', 'derived').pluck('id'), [2]);
          expect(await joined().delete(), 1);
        } else {
          await expectLater(
            joined().update({'target.key': 'derived'}),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            joined().delete(),
            throwsA(isA<LaconicException>()),
          );
          expect(await query().count(), 5);
        }
      });

      test('updateOrInsert updates at most one matching row', () async {
        await query().updateOrInsert(
          {'key': 'shared'},
          {'id': 10, 'group': 0, 'payload': '{}'},
        );
        await query().whereIn('id', [1, 2]).update({'key': 'shared'});
        await query().updateOrInsert({'key': 'shared'}, {'key': 'single'});
        expect(await query().where('key', 'single').count(), 1);
      });

      test('chunk callbacks stop early and receive page numbers', () async {
        final seen = <Object?>[];
        final pages = <int>[];
        expect(
          await query().orderBy('id').chunk(2, (
            List<LaconicResult> rows,
            int page,
          ) async {
            seen.addAll(rows.map((r) => r['id']));
            pages.add(page);
            return false;
          }),
          isFalse,
        );
        expect(seen, [1, 2]);
        expect(pages, [1]);
        seen.clear();
        expect(
          await query().chunkById(2, (List<LaconicResult> rows) {
            seen.addAll(rows.map((r) => r['id']));
            return false;
          }),
          isFalse,
        );
        expect(seen, [1, 2]);
        final indexes = <int>[];
        expect(
          await query().orderBy('id').each((LaconicResult row, int index) {
            indexes.add(index);
            return index < 2;
          }, count: 2),
          isFalse,
        );
        expect(indexes, [0, 1, 2]);
      });

      test(
        'keyset aliases identify result columns instead of tables',
        () async {
          final seen = <Object?>[];
          final q = db
              .table('$table as target')
              .select(['target.id as cursor_key'])
              .offset(1)
              .limit(3);
          expect(
            await q.chunkById(
              2,
              (List<LaconicResult> rows, int page) {
                seen.addAll(rows.map((r) => r['cursor_key']));
                return true;
              },
              column: 'target.id',
              alias: 'cursor_key',
            ),
            isTrue,
          );
          expect(seen, [2, 3, 4]);
        },
      );

      test(
        'JSON readers, nulls and object values preserve their types',
        () async {
          expect(await query().where('id', 1).value('payload->name'), 'name-1');
          expect(
            await query().where('id', 1).soleValue('payload->name'),
            'name-1',
          );
          expect(
            await query().where('id', 1).pluck('payload->name', key: 'id'),
            {1: 'name-1'},
          );
          await query().where('id', 1).update({
            'payload->name': null,
            'payload->items': [8, 9],
            'payload->nested': {'value': 44},
          });
          expect(
            await query().where('id', 1).whereNull('payload->name').exists(),
            isTrue,
          );
          expect(
            await query()
                .where('id', 1)
                .whereNotNull('payload->missing')
                .exists(),
            isFalse,
          );
          expect(await query().where('payload->items[1]', 9).value('id'), 1);
          expect(
            await query().where('payload->nested->value', 44).value('id'),
            1,
          );
        },
      );

      test('quotes identifiers and aliases throughout CRUD', () async {
        final rows =
            await db
                .table('$table as select')
                .select(['select.key as order', 'select.group'])
                .where('select.group', 2)
                .orderBy('select.key')
                .get();
        expect(rows.single['order'], 'row-2');
        expect(await query().where('group', 2).update({'key': 'changed'}), 1);
        expect(await query().where('key', 'changed').value('group'), 2);
        expect(await query().groupBy('group').having('group', 2).count(), 1);
        await query().where('id', 1).update({'odd"name]': 'escaped'});
        expect(await query().where('id', 1).value('odd"name]'), 'escaped');
        final aliased = db.table('$table as target').where('target.id', 4);
        expect(await aliased.update({'target.key': 'aliased'}), 1);
        expect(await query().where('key', 'aliased').value('id'), 4);
        expect(await aliased.delete(), 1);
      });

      test('JSON paths select, compare scalars and update siblings', () async {
        expect(
          await query()
              .where('payload->enabled', true)
              .orderBy('id')
              .pluck('id'),
          [1, 3, 5],
        );
        expect(await query().where('payload->name', 'name-2').value('id'), 2);
        expect(
          await query()
              .where('payload->count', 3, comparator: '>')
              .orderBy('id')
              .pluck('id'),
          [4, 5],
        );
        expect(await query().where('payload->items[0]', 2).value('id'), 2);
        await query().where('id', 2).update({
          'payload->enabled': true,
          'payload->name': "O'Reilly",
          'payload->nested->value': 99,
          'payload->items[0]': 42,
        });
        expect(
          await query().where('payload->enabled', true).where('id', 2).exists(),
          isTrue,
        );
        final rows =
            await query()
                .select([
                  'payload->name as name',
                  'payload->nested->value as value',
                ])
                .where('id', 2)
                .get();
        expect(rows.single['name'], "O'Reilly");
        expect('${rows.single['value']}', '99');
        expect(await query().where('payload->items[0]', 42).value('id'), 2);
        expect(await query().where('payload->count', 2).value('id'), 2);
      });

      test(
        'JSON sibling bindings follow assignment order across columns',
        () async {
          await query().where('id', 1).update({
            'payload->name': 'interleaved',
            'key': 'ordinary',
            'payload->nested->value': 44,
          });
          expect(await query().where('key', 'ordinary').value('id'), 1);
          expect(
            await query().where('payload->name', 'interleaved').value('id'),
            1,
          );
          expect(
            await query().where('payload->nested->value', 44).value('id'),
            1,
          );
        },
      );

      test('quoted JSON keys retain dots and arrow characters', () async {
        expect(await query().where('payload->"a.b"', 2).value('id'), 2);
        expect(await query().where('payload->"a->b"', 3).value('id'), 3);
        expect(
          await query().whereJsonContainsKey('payload->items[0]').count(),
          5,
        );
        await query().where('id', 2).update({
          'payload->"a.b"': 11,
          'payload->"a->b"': 12,
        });
        expect(await query().where('payload->"a.b"', 11).value('id'), 2);
        expect(await query().where('payload->"a->b"', 12).value('id'), 2);
      });

      test('joined writes preserve joins and their bindings', () async {
        QueryBuilder joined() => query()
            .join(
              related,
              (j) => j
                  .on('$table.id', '$related.parent_id')
                  .where('$related.label', 'match'),
            )
            .where('$table.id', 1, comparator: '>');
        expect(await joined().update({'key': 'joined'}), 1);
        expect(await query().where('key', 'joined').pluck('id'), [2]);
        expect(await joined().delete(), 1);
        expect(await query().orderBy('id').pluck('id'), [1, 3, 4, 5]);
      });

      test('limited writes retain their limit', () async {
        expect(
          await query().where('id', 0, comparator: '>').limit(1).update({
            'key': 'one',
          }),
          1,
        );
        expect(await query().where('key', 'one').count(), 1);
        expect(
          await query().where('id', 0, comparator: '>').limit(1).delete(),
          1,
        );
        expect(await query().count(), 4);
        expect(
          await query().where('id', 0, comparator: '>').limit(0).update({
            'key': 'none',
          }),
          0,
        );
      });

      test('unsupported write scopes fail before executing', () async {
        for (final q in [
          query().groupBy('group'),
          query().distinct(),
          query().union(query()),
          query().fromRaw(table),
        ]) {
          await expectLater(
            q.update({'key': 'wrong'}),
            throwsA(isA<LaconicException>()),
          );
        }
        expect(await query().where('key', 'wrong').count(), 0);
      });

      test(
        'chunk and lazy preserve the original offset and total limit',
        () async {
          final q = query().orderBy('id').offset(1).limit(3);
          final sql = q.toSql();
          final seen = <Object?>[];
          await q.chunk(2, (rows) async {
            seen.addAll(rows.map((r) => r['id']));
          });
          expect(seen, [2, 3, 4]);
          expect(await q.lazy(2).map((r) => r['id']).toList(), [2, 3, 4]);
          expect(q.toSql(), sql);
          expect(
            await query().orderBy('id').limit(0).lazy(2).toList(),
            isEmpty,
          );
        },
      );

      test(
        'chunkById and lazyById preserve total limit and initial offset',
        () async {
          final q = query().offset(1).limit(3);
          final seen = <Object?>[];
          await q.chunkById(2, (rows) async {
            seen.addAll(rows.map((r) => r['id']));
          });
          expect(seen, [2, 3, 4]);
          expect(await q.lazyById(2).map((r) => r['id']).toList(), [2, 3, 4]);
          expect(await query().limit(0).lazyById(2).toList(), isEmpty);
        },
      );
    });
  }
}
