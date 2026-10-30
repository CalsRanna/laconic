import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class SchemaTableOptionsRegressions {
  static void register(
    Laconic Function() createDatabase, {
    required bool sqlite,
    String? namespace,
  }) {
    group('Schema table options', () {
      const name = 'laconic_table_options';
      const temporary = 'laconic_options_temporary';
      const unusual = 'laconic_options\'"`]';
      final table = '${namespace ?? 'main'}.$name';
      final quotedTable = '${namespace ?? 'main'}.$unusual';
      final postgres = namespace == 'public';
      final sqlserver = namespace == 'dbo';
      final mysql = !sqlite && !postgres && !sqlserver;
      late Laconic db;

      setUp(() async {
        db = createDatabase();
        await db.schema.dropIfExists(table);
        await db.schema.dropIfExists(quotedTable);
      });
      tearDown(() async {
        try {
          await db.schema.dropIfExists(quotedTable);
          await db.schema.dropIfExists(table);
        } finally {
          await db.close();
        }
      });

      final options = <String, void Function(Blueprint)>{
        'engine': (t) => t.engine('InnoDB'),
        'innoDb': (t) => t.innoDb(),
        'charset': (t) => t.charset('utf8mb4'),
        'collation': (t) => t.collation('utf8mb4_bin'),
      };

      for (final option in options.entries) {
        test(
          'creates with ${option.key} or rejects unsupported options',
          () async {
            Future<void> create() => db.schema.create(table, (t) {
              t.string('label');
              option.value(t);
            });
            if (!mysql) {
              await expectLater(create(), throwsA(isA<LaconicException>()));
              expect(await db.schema.hasTable(table), isFalse);
              return;
            }
            await create();
            final row =
                (await db.select(
                  'select engine as engine, table_collation as table_collation from information_schema.tables '
                  'where table_schema = ? and table_name = ?',
                  [namespace, name],
                )).single;
            if (option.key == 'engine' || option.key == 'innoDb') {
              expect(row['engine'], 'InnoDB');
            } else if (option.key == 'charset') {
              expect(row['table_collation'], startsWith('utf8mb4_'));
            } else {
              expect(row['table_collation'], 'utf8mb4_bin');
              expect(
                (await db.schema.getColumns(table)).single.collation,
                'utf8mb4_bin',
              );
            }
          },
        );
      }

      test('rejects create-only options before altering any columns', () async {
        await db.schema.create(table, (t) => t.integer('id'));
        for (final option in [
          ...options.values,
          (Blueprint t) => t.temporary(),
        ]) {
          await expectLater(
            db.schema.table(table, (t) {
              t.integer('unexecuted').nullable();
              option(t);
            }),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.getColumnListing(table), ['id']);
        }
      });

      if (mysql) {
        test(
          'table defaults compose and explicit column collation wins',
          () async {
            await db.schema.create(table, (t) {
              t.innoDb().charset('utf8mb4').collation('utf8mb4_bin');
              t.string('inherited');
              t.string('overridden').collation('utf8mb4_unicode_ci');
            });
            final columns = await db.schema.getColumns(table);
            expect(columns[0].collation, 'utf8mb4_bin');
            expect(columns[1].collation, 'utf8mb4_unicode_ci');
          },
        );

        test(
          'temporary tables reject foreign keys and full-text indexes before execution',
          () {
            for (final define in <void Function(Blueprint)>[
              (t) => t.foreign(['id']).references(['id']).on(name),
              (t) => t.fullText(['label']),
            ]) {
              final blueprint = Blueprint(temporary)..temporary();
              blueprint.integer('id');
              blueprint.text('label');
              define(blueprint);
              expect(
                () => db.grammar.compileCreateTable(blueprint),
                throwsA(isA<LaconicException>()),
              );
            }
          },
        );
      }

      if (sqlite || postgres) {
        test('temporary operations reject a permanent schema', () async {
          await expectLater(
            db.schema.create(table, (t) {
              t.temporary();
              t.integer('id');
            }),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasTable(table), isFalse);
          await db.schema.create(table, (t) => t.integer('id'));
          expect(
            () => db.schema.drop(table, temporary: true),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasTable(table), isTrue);
        });
      }

      test(
        'creates, replaces, and clears table comments with quoted names',
        () async {
          const initial = "Owner's 表注释; -- ?";
          if (sqlite) {
            await expectLater(
              db.schema.create(table, (t) {
                t.integer('id');
                t.comment(initial);
              }),
              throwsA(isA<LaconicException>()),
            );
            expect(await db.schema.hasTable(table), isFalse);
            return;
          }
          for (final target in [name, quotedTable]) {
            await db.schema.create(target, (t) {
              t.integer('id').comment('column comment');
              t.comment(initial);
            });
            Future<String?> read() => _comment(
              db,
              target == name ? table : target,
              postgres: postgres,
              sqlserver: sqlserver,
            );
            expect(await read(), initial);
            await db.schema.table(target, (t) => t.integer('added').nullable());
            expect(await read(), initial);
            final replacement =
                mysql ? '新 comment\nline' : '新 comment\\path\nline';
            await db.schema.table(target, (t) => t.comment(replacement));
            expect(await read(), replacement);
            expect(
              (await db.schema.getColumns(target)).first.comment,
              'column comment',
            );
            for (var i = 0; i < 2; i++) {
              await db.schema.table(target, (t) => t.comment(''));
              expect(await read() ?? '', isEmpty);
            }
            await db.schema.table(target, (t) => t.comment(initial));
            expect(await read(), initial);
          }
        },
      );

      test(
        'invalid comments fail before creating or altering a table',
        () async {
          final invalid =
              sqlite
                  ? ['unsupported']
                  : mysql
                  ? ['back\\slash', 'nul\u0000text']
                  : sqlserver
                  ? ['x' * 3751]
                  : ['nul\u0000text'];
          for (final comment in invalid) {
            await expectLater(
              db.schema.create(table, (t) {
                t.integer('id');
                t.comment(comment);
              }),
              throwsA(isA<LaconicException>()),
            );
            expect(await db.schema.hasTable(table), isFalse);
          }
          await db.schema.create(table, (t) => t.integer('id'));
          for (final comment in invalid) {
            await expectLater(
              db.schema.table(table, (t) {
                t.integer('unexecuted').nullable();
                t.comment(comment);
              }),
              throwsA(isA<LaconicException>()),
            );
            expect(await db.schema.getColumnListing(table), ['id']);
          }
          if (sqlite) {
            await db.schema.table(
              table,
              (t) => t.index(['id'], name: 'options_id'),
            );
            for (final alter in <void Function(Blueprint)>[
              (t) => t.dropColumn('id'),
              (t) => t.renameIndex('options_id', 'options_renamed'),
            ]) {
              await expectLater(
                db.schema.table(table, (t) {
                  alter(t);
                  t.comment('unsupported');
                }),
                throwsA(isA<LaconicException>()),
              );
              expect(await db.schema.getColumnListing(table), ['id']);
              expect(await db.schema.hasIndex(table, 'options_id'), isTrue);
            }
          }
        },
      );

      test('temporary tables stay on one session and support indexes', () async {
        Future<void> create() => db.schema.create(temporary, (t) {
          t.temporary();
          t.integer('id');
          t.string('label');
          t.unique(['label'], name: 'options_temp_label');
          if (mysql) t.innoDb().charset('utf8mb4').collation('utf8mb4_bin');
        });
        if (sqlserver) {
          await expectLater(create(), throwsA(isA<LaconicException>()));
          expect(await db.schema.hasTable(temporary), isFalse);
          return;
        }
        await db.transaction(() async {
          await create();
          try {
            await db.table(temporary).insert([
              {'id': 1, 'label': '临时'},
            ]);
            expect(await db.table(temporary).value('label'), '临时');
            if (sqlite) {
              expect(await db.schema.hasTable('temp.$temporary'), isTrue);
              expect(await db.schema.hasTable('main.$temporary'), isFalse);
              expect(
                await db.schema.hasIndex(
                  'temp.$temporary',
                  'options_temp_label',
                ),
                isTrue,
              );
            } else if (postgres) {
              final rows = await db.select(
                'select relpersistence::text as relpersistence from pg_class where oid = to_regclass(\$1)',
                [temporary],
              );
              expect(rows.single['relpersistence'], 't');
            }
            final other = createDatabase();
            try {
              await expectLater(
                other.table(temporary).get(),
                throwsA(isA<LaconicException>()),
              );
            } finally {
              await other.close();
            }
          } finally {
            await db.schema.drop(temporary, temporary: true);
          }
        });
      });

      if (!sqlserver) {
        test(
          'temporary creation with comments and indexes does not commit a transaction',
          () async {
            await db.schema.create(table, (t) => t.integer('id'));
            await expectLater(
              db.transaction(() async {
                await db.table(table).insert([
                  {'id': 1},
                ]);
                await db.schema.create(temporary, (t) {
                  t.temporary();
                  t.integer('id');
                  t.unique(['id'], name: 'options_temp_unique');
                  t.index(['id'], name: 'options_temp_index');
                  if (!sqlite) t.comment("Temporary's comment");
                });
                try {
                  await db.table(temporary).insert([
                    {'id': 2},
                  ]);
                  expect(await db.table(temporary).value('id'), 2);
                } finally {
                  await db.schema.drop(temporary, temporary: true);
                }
                throw LaconicException('rollback');
              }),
              throwsA(
                isA<LaconicException>().having(
                  (e) => e.message,
                  'message',
                  'rollback',
                ),
              ),
            );
            expect(await db.table(table).count(), 0);
          },
        );
      }

      test(
        'temporary-only drops preserve a permanent table with the same name',
        () async {
          await db.schema.create(table, (t) => t.integer('id'));
          if (sqlserver) {
            await expectLater(
              () => db.schema.drop(name, temporary: true),
              throwsA(isA<LaconicException>()),
            );
            await expectLater(
              () => db.schema.dropIfExists(name, temporary: true),
              throwsA(isA<LaconicException>()),
            );
            expect(await db.schema.hasTable(table), isTrue);
            return;
          }
          await db.transaction(() async {
            await db.table(table).insert([
              {'id': 1},
            ]);
            await db.schema.dropIfExists(name, temporary: true);
            expect(await db.table(table).value('id'), 1);
            await db.schema.create(name, (t) {
              t.temporary();
              t.integer('id');
              t.unique(['id'], name: 'options_shadow_index');
            });
            try {
              await db.table(name).insert([
                {'id': 2},
              ]);
              expect(await db.table(name).value('id'), 2);
              if (sqlite || postgres) {
                final tempTable = '${sqlite ? 'temp' : 'pg_temp'}.$name';
                expect(
                  await db.schema.hasIndex(tempTable, 'options_shadow_index'),
                  isTrue,
                );
                expect(
                  await db.schema.hasIndex(table, 'options_shadow_index'),
                  isFalse,
                );
              }
            } finally {
              await db.schema.drop(name, temporary: true);
            }
            await db.schema.dropIfExists(name, temporary: true);
            expect(await db.table(table).value('id'), 1);
          });
        },
      );
    });
  }

  static Future<String?> _comment(
    Laconic db,
    String table, {
    required bool postgres,
    required bool sqlserver,
  }) async {
    final parts = db.grammar.schemaTableParts(table);
    final rows =
        postgres
            ? await db.select(
              "select obj_description(to_regclass(\$1), 'pg_class') as comment",
              [db.grammar.quoteSchemaIdentifier(table, qualified: true)],
            )
            : sqlserver
            ? await db.select(
              "select cast(p.value as nvarchar(3750)) as comment from sys.tables t "
              "join sys.schemas s on s.schema_id = t.schema_id "
              "left join sys.extended_properties p on p.class = 1 and p.major_id = t.object_id "
              "and p.minor_id = 0 and p.name = N'MS_Description' "
              'where s.name = ? and t.name = ?',
              parts,
            )
            : await db.select(
              'select table_comment as comment from information_schema.tables '
              'where table_schema = ? and table_name = ?',
              parts,
            );
    return rows.single['comment'] as String?;
  }
}
