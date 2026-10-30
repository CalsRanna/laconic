import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class SchemaFeatureRegressions {
  static void register(
    Laconic Function() createDatabase, {
    required bool sqlite,
    bool mariadb = false,
    String? namespace,
  }) {
    group('Schema indexes, modifiers, and generated columns', () {
      const name = 'laconic_schema_features';
      const pending = 'laconic_schema_pending';
      final table = '${namespace ?? 'main'}.$name';
      final postgres = namespace == 'public';
      final sqlserver = namespace == 'dbo';
      final mysql = !sqlite && !postgres && !sqlserver;
      late Laconic db;

      setUp(() async {
        db = createDatabase();
        if (sqlite) await db.statement('pragma foreign_keys = on');
        await db.schema.dropIfExists(table);
        await db.schema.dropIfExists(pending);
      });
      tearDown(() async {
        try {
          await db.schema.dropIfExists(pending);
          await db.schema.dropIfExists(table);
        } finally {
          await db.close();
        }
      });

      test('renames and drops compound unique and ordinary indexes', () async {
        const renamed = 'features odd\'"`]';
        await db.schema.create(table, (t) {
          t.integer('a');
          t.integer('b');
          t.unique(['a', 'b'], name: 'features_pair');
          t.index(['b'], name: 'features_b');
        });
        await db.table(table).insert([
          {'a': 1, 'b': 2},
        ]);
        await db.schema.table(table, (t) {
          t.renameIndex('features_pair', 'features_intermediate');
          t.renameIndex('features_intermediate', renamed);
          t.renameIndex('features_b', 'features_b_new');
        });
        expect(await db.schema.hasIndex(table, 'features_pair'), isFalse);
        final indexes = await db.schema.getIndexes(table);
        final pair = indexes.singleWhere((i) => i.name == renamed);
        expect(pair.columns, ['a', 'b']);
        expect(pair.unique, isTrue);
        expect(await db.schema.hasIndex(table, 'features_b_new'), isTrue);
        await expectLater(
          db.table(table).insert([
            {'a': 1, 'b': 2},
          ]),
          throwsA(isA<LaconicException>()),
        );
        await db.schema.table(table, (t) {
          t.dropUnique(renamed);
          t.dropIndex('features_b_new');
        });
        expect(await db.schema.getIndexes(table), isEmpty);
        await db.table(table).insert([
          {'a': 1, 'b': 2},
        ]);
        expect(await db.table(table).count(), 2);
      });

      test('drops a named composite primary key without losing rows', () async {
        await db.schema.create(table, (t) {
          t.integer('a');
          t.integer('b');
          t.primary(['a', 'b'], name: 'features_pk');
        });
        await db.table(table).insert([
          {'a': 1, 'b': 2},
        ]);
        await db.schema.table(table, (t) => t.dropPrimary('features_pk'));
        expect(
          (await db.schema.getIndexes(table)).where((i) => i.primary),
          isEmpty,
        );
        await db.table(table).insert([
          {'a': 1, 'b': 2},
        ]);
        expect(await db.table(table).count(), 2);
        await expectLater(
          db.schema.table(
            table,
            (t) => t.unique(['a'], name: 'features_invalid'),
          ),
          throwsA(isA<LaconicException>()),
        );
      });

      test('creates, searches, renames, and drops full-text indexes', () async {
        void define(Blueprint t) {
          t.integer('id');
          t.text('title').nullable();
          t.text('body').nullable();
          final index = t.fullText(['title', 'body'], name: 'features_search');
          if (postgres) index.language('english');
        }

        if (sqlite || sqlserver) {
          await expectLater(
            db.schema.create(table, define),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasTable(table), isFalse);
          await db.schema.create(table, (t) => t.integer('id'));
          await expectLater(
            db.schema.table(table, (t) {
              t.integer('unexecuted').nullable();
              t.fullText(['id']);
            }),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasColumn(table, 'unexecuted'), isFalse);
          await expectLater(
            db.schema.table(table, (t) => t.dropFullText('missing')),
            throwsA(isA<LaconicException>()),
          );
          return;
        }
        await db.schema.create(table, define);
        await db.table(table).insert([
          {
            'id': 1,
            'title': 'Database migration handbook',
            'body': 'Laconic schema builder',
          },
          {'id': 2, 'title': 'Gardening guide', 'body': null},
          {'id': 3, 'title': null, 'body': 'Database migrations and indexes'},
        ]);
        Future<dynamic> matches() => db
            .table(table)
            .whereFullText(['title', 'body'], 'database')
            .orderBy('id')
            .pluck('id');
        expect(await matches(), [1, 3]);
        final index = (await db.schema.getIndexes(table)).single;
        expect(index.type, postgres ? 'gin' : 'fulltext');
        if (postgres) {
          expect(index.definition!.toLowerCase(), contains('coalesce'));
          await db.transaction(() async {
            await db.statement('set local enable_seqscan = off');
            final query = db.table(table).whereFullText([
              'title',
              'body',
            ], 'database');
            final plan = await db.select(
              'explain ${query.toSql()}',
              query.getBindings(),
            );
            expect(
              plan.map((r) => r.toMap().values.join()).join('\n'),
              contains('features_search'),
            );
          });
        }
        await db.schema.table(
          table,
          (t) => t.renameIndex('features_search', 'features_search_new'),
        );
        expect(await matches(), [1, 3]);
        await db.schema.table(
          table,
          (t) => t.dropFullText('features_search_new'),
        );
        expect(await db.schema.getIndexes(table), isEmpty);
        await db.schema.table(table, (t) => t.fullText(['body']));
        expect(
          await db.schema.hasIndex(
            table,
            '${table.replaceAll('.', '_')}_body_fulltext',
          ),
          isTrue,
        );
      });

      test('current-time defaults work on create, add, and change', () async {
        await db.schema.create(table, (t) {
          t.id();
          t.integer('marker');
          t.timestamp('created', precision: 3).useCurrent();
        });
        await db.table(table).insert([
          {'marker': 1},
        ]);
        await db.schema.table(
          table,
          (t) => t.timestamp('added', precision: 3).useCurrent(),
        );
        var row = await db.table(table).first();
        expect(row['created'], isNotNull);
        expect(row['added'], isNotNull);
        await db.schema.table(
          table,
          (t) => t.timestamp('created', precision: 3).useCurrent().change(),
        );
        await db.table(table).insert([
          {'marker': 2},
        ]);
        row = await db.table(table).where('marker', 2).first();
        expect(row['created'], isNotNull);
        final columns = await db.schema.getColumns(table);
        expect(
          columns
              .singleWhere((c) => c.name == 'created')
              .defaultValue!
              .toLowerCase(),
          contains(sqlserver ? 'getdate' : 'current_timestamp'),
        );
        expect(await db.table(table).orderBy('id').pluck('id'), [1, 2]);
      });

      test('collations apply on create and change', () async {
        final collation =
            mysql
                ? 'utf8mb4_bin'
                : postgres
                ? 'C'
                : sqlserver
                ? 'Latin1_General_100_BIN2'
                : 'BINARY';
        await db.schema.create(table, (t) {
          t.integer('id');
          final column = t.string('label', length: 80).collation(collation);
          if (mysql) column.charset('utf8mb4');
        });
        await db.table(table).insert([
          {'id': 1, 'label': 'Case'},
          {'id': 2, 'label': 'case'},
        ]);
        expect(await db.table(table).where('label', 'Case').count(), 1);
        await db.schema.table(table, (t) {
          final column =
              t.string('label', length: 100).collation(collation).change();
          if (mysql) column.charset('utf8mb4');
        });
        expect(
          (await db.schema.getColumns(
            table,
          )).singleWhere((c) => c.name == 'label').collation,
          collation,
        );
        expect(await db.table(table).where('label', 'case').count(), 1);
      });

      test('column comments round-trip, change, and clear', () async {
        if (sqlite) {
          await expectLater(
            db.schema.create(
              table,
              (t) => t.integer('id').comment('unsupported'),
            ),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasTable(table), isFalse);
          return;
        }
        const original = "A column's 中文说明";
        await db.schema.create(
          table,
          (t) => t.string('label', length: 80).comment(original),
        );
        expect((await db.schema.getColumns(table)).single.comment, original);
        await db.schema.table(
          table,
          (t) => t.integer('added').nullable().comment('added comment'),
        );
        expect(
          (await db.schema.getColumns(
            table,
          )).singleWhere((c) => c.name == 'added').comment,
          'added comment',
        );
        await db.schema.table(
          table,
          (t) => t.string('label', length: 90).comment('changed').change(),
        );
        expect((await db.schema.getColumns(table)).first.comment, 'changed');
        await db.schema.table(
          table,
          (t) => t.string('label', length: 100).change(),
        );
        expect((await db.schema.getColumns(table)).first.comment, isNull);
      });

      test('MySQL column positions and automatic update timestamps', () async {
        await db.schema.create(table, (t) {
          t.id();
          t.integer('marker');
        });
        if (!mysql) {
          for (final define in <void Function(Blueprint)>[
            (t) => t.integer('unexecuted').first(),
            (t) => t.integer('unexecuted').after('id'),
            (t) => t.string('unexecuted').charset('utf8mb4'),
            (t) => t.timestamp('unexecuted').useCurrentOnUpdate(),
          ]) {
            await expectLater(
              db.schema.table(table, (t) {
                t.integer('before_error').nullable();
                define(t);
              }),
              throwsA(isA<LaconicException>()),
            );
            expect(await db.schema.hasColumn(table, 'before_error'), isFalse);
          }
          return;
        }
        await db.schema.table(table, (t) {
          t.integer('leading').nullable().first();
          t
              .timestamp('updated', precision: 3)
              .useCurrent()
              .useCurrentOnUpdate()
              .after('id');
        });
        expect(await db.schema.getColumnListing(table), [
          'leading',
          'id',
          'updated',
          'marker',
        ]);
        await db.schema.table(
          table,
          (t) => t.integer('leading').nullable().after('marker').change(),
        );
        expect(await db.schema.getColumnListing(table), [
          'id',
          'updated',
          'marker',
          'leading',
        ]);
        await db.table(table).insert([
          {'marker': 1, 'updated': '2001-01-01 00:00:00'},
        ]);
        final before = (await db.table(table).first())['updated'];
        await db.table(table).where('marker', 1).update({'marker': 2});
        expect(
          (await db.table(table).first())['updated'],
          isNot(equals(before)),
        );
        await db.schema.table(
          table,
          (t) => t.timestamp('updated', precision: 3).useCurrent().change(),
        );
        await db.table(table).where('marker', 2).update({
          'updated': '2001-01-01 00:00:00',
        });
        final fixed = (await db.table(table).first())['updated'];
        await db.table(table).where('marker', 2).update({'marker': 3});
        expect((await db.table(table).first())['updated'], fixed);
      });

      test(
        'generated values survive writes, added columns, and table rebuilds',
        () async {
          void generated(
            Blueprint t,
            String name,
            String expression, {
            bool stored = true,
          }) {
            if (sqlserver) {
              t.computed(name, expression).persisted(stored);
            } else if (stored) {
              t.integer(name).storedAs(expression).nullable();
            } else {
              t.integer(name).virtualAs(expression).nullable();
            }
          }

          await db.schema.create(table, (t) {
            t.id();
            t.integer('quantity');
            t.integer('price');
            generated(t, 'total', 'quantity * price');
            if (!postgres) {
              generated(t, 'preview', 'quantity + price', stored: false);
            }
          });
          await db.table(table).insert([
            {'quantity': 3, 'price': 7},
          ]);
          expect((await db.table(table).first())['total'], 21);
          if (!postgres) expect((await db.table(table).first())['preview'], 10);
          await expectLater(
            db.table(table).where('id', 1).update({'total': 1}),
            throwsA(isA<LaconicException>()),
          );
          await db.table(table).where('id', 1).update({'quantity': 4});
          expect((await db.table(table).first())['total'], 28);
          await db.schema.table(table, (t) {
            generated(t, 'extra', 'price + 5');
            t.index(['extra'], name: 'features_generated');
          });
          expect(await db.table(table).value('extra'), 12);
          if (!postgres) {
            await db.schema.table(
              table,
              (t) => generated(t, 'added_virtual', 'price + 2', stored: false),
            );
            expect(await db.table(table).value('added_virtual'), 9);
          }
          if (sqlite) {
            await db.schema.table(table, (t) => t.integer('quantity').change());
          }
          await db.schema.table(table, (t) => t.integer('note').nullable());
          await db.schema.table(table, (t) => t.dropColumn('note'));
          expect(await db.table(table).count(), 1);
          final row =
              await db.table(table).select(['id', 'total', 'extra']).first();
          expect(row['id'], 1);
          expect(row['total'], 28);
          expect(row['extra'], 12);
          expect(await db.schema.hasIndex(table, 'features_generated'), isTrue);
          final columns = await db.schema.getColumns(table);
          for (final name in ['total', 'extra', if (!postgres) 'preview']) {
            final column = columns.singleWhere((c) => c.name == name);
            expect(column.generated, isTrue, reason: name);
            expect(column.generation, isNotEmpty, reason: name);
          }
          await expectLater(
            db.schema.table(table, (t) {
              t.integer('unexecuted').nullable();
              t.integer('total').change();
            }),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasColumn(table, 'unexecuted'), isFalse);
          await db.schema.table(table, (t) {
            t.dropIndex('features_generated');
            t.dropColumn('extra');
            generated(t, 'extra', 'price + 10');
          });
          expect(await db.table(table).value('extra'), 17);
        },
      );

      test('invalid generated columns and modifiers fail before DDL', () async {
        for (final define in <void Function(Blueprint)>[
          (t) => t.integer('value').storedAs('1').defaultTo(2),
          (t) => t.integer('value').virtualAs(''),
          (t) => t.id().storedAs('1'),
          (t) => t.integer('value').useCurrent(),
          (t) => t.integer('value').first().after('id'),
          (t) => t.integer('value').first(),
          (t) => t.integer('value').storedAs('1').change(),
          if (postgres) (t) => t.integer('value').virtualAs('1'),
          if (sqlserver) (t) => t.integer('value').storedAs('1'),
          if (!sqlserver) (t) => t.computed('value', '1'),
          if (mariadb) (t) => t.integer('value').storedAs('1'),
          if (sqlserver) (t) => t.computed('value', '1').nullable(false),
          if (mysql)
            (t) {
              t.text('value');
              t.fullText(['value']).language('english');
            },
        ]) {
          await expectLater(
            db.schema.create(pending, define),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasTable(pending), isFalse);
        }
      });

      if (!mariadb) {
        test(
          'generated NOT NULL constraints are enforced where supported',
          () async {
            await db.schema.create(table, (t) {
              t.integer('quantity').nullable();
              if (sqlserver) {
                t.computed('total', 'quantity + 1').persisted().nullable(false);
              } else {
                t.integer('total').storedAs('quantity + 1');
              }
            });
            expect(
              (await db.schema.getColumns(
                table,
              )).singleWhere((c) => c.name == 'total').nullable,
              isFalse,
            );
            await expectLater(
              db.table(table).insert([
                {'quantity': null},
              ]),
              throwsA(isA<LaconicException>()),
            );
            await db.table(table).insert([
              {'quantity': 2},
            ]);
            expect(await db.table(table).value('total'), 3);
          },
        );
      }

      if (sqlite) {
        test(
          'index-only rename preserves expression, filter, ordering, and data',
          () async {
            await db.schema.create(table, (t) {
              t.id();
              t.string('label');
              t.integer('active');
            });
            await db.table(table).insert([
              {'label': 'Mixed', 'active': 1},
            ]);
            await db.statement(
              'create unique index main.features_expression on $name (lower(label) collate nocase desc) where active = 1',
            );
            final blueprint = Blueprint(table)
              ..renameIndex('features_expression', 'features_expression_new');
            final snapshot = db.grammar.compileSchemaObjects(table);
            final objects = await db.select(snapshot.sql, snapshot.bindings);
            final statements =
                db.grammar
                    .compileAlterTable(
                      blueprint,
                      objects: objects.map((r) => r.toMap()).toList(),
                    )
                    .map((q) => q.sql)
                    .toList();
            await db.transaction(() async {
              await db.schema.table(
                table,
                (t) => t.renameIndex(
                  'features_expression',
                  'features_expression_new',
                ),
              );
              expect(
                (await db.select(
                  'pragma foreign_keys',
                )).single.toMap().values.single,
                1,
              );
            });
            final index = (await db.schema.getIndexes(
              table,
            )).singleWhere((i) => !i.primary);
            expect(
              index.definition!.toLowerCase(),
              contains('lower(label) collate nocase desc'),
            );
            expect(index.definition, contains('where active = 1'));
            expect(
              statements.any(
                (s) =>
                    s.startsWith('create table') || s.startsWith('insert into'),
              ),
              isFalse,
            );
            await expectLater(
              db.table(table).insert([
                {'label': 'MIXED', 'active': 1},
              ]),
              throwsA(isA<LaconicException>()),
            );
            await db.table(table).insert([
              {'label': 'MIXED', 'active': 0},
            ]);
            await expectLater(
              db.schema.table(table, (t) {
                t.renameIndex('features_expression_new', 'features_temporary');
                t.renameIndex('missing', 'features_missing');
              }),
              throwsA(isA<LaconicException>()),
            );
            expect(
              await db.schema.hasIndex(table, 'features_expression_new'),
              isTrue,
            );
            expect(
              await db.schema.hasIndex(table, 'features_temporary'),
              isFalse,
            );
            await db.schema.create(pending, (t) {
              t.integer('value');
              t.index(['value'], name: 'features_collision');
            });
            await db.transaction(() async {
              await expectLater(
                db.schema.table(
                  table,
                  (t) => t.renameIndex(
                    'features_expression_new',
                    'features_collision',
                  ),
                ),
                throwsA(isA<LaconicException>()),
              );
              expect(
                await db.schema.hasIndex(table, 'features_expression_new'),
                isTrue,
              );
            });
            await expectLater(
              db.schema.table(table, (t) {
                t.renameColumn('label', 'label_new');
                t.renameIndex('features_expression_new', 'features_temporary');
              }),
              throwsA(isA<LaconicException>()),
            );
            expect(await db.schema.hasColumn(table, 'label'), isTrue);
            await db.schema.table(table, (t) {
              t.string('label', length: 300).change();
              t.renameIndex(
                'features_expression_new',
                'features_after_rebuild',
              );
            });
            expect(
              await db.schema.hasIndex(table, 'features_after_rebuild'),
              isTrue,
            );
            expect(await db.table(table).count(), 2);
          },
        );
      }
    });
  }
}
