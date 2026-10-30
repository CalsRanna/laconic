import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

import 'migrator_regressions.dart';

abstract final class MigrationDeploymentRegressions {
  static void register(Laconic Function() createDatabase) {
    group('Migration deployment', () {
      const history = 'deployment_history';
      const items = 'deployment_items';
      late Laconic db;
      setUp(() async {
        db = createDatabase();
        await db.schema.dropIfExists(items);
        await db.schema.dropIfExists(history);
      });
      tearDown(() async {
        try {
          await db.schema.dropIfExists(items);
          await db.schema.dropIfExists(history);
        } finally {
          await db.close();
        }
      });
      test(
        'conditions remain pending, do not consume batches, and do not suppress down or pretend',
        () async {
          var enabled = false;
          var evaluations = 0;
          final migration = TestMigration(
            '001_conditional',
            (target) => target.schema.create(items, (t) => t.id()),
            (target) => target.schema.drop(items),
            condition: (target) async {
              expect(target, same(db));
              evaluations++;
              return enabled;
            },
          );
          final later = TestMigration('002_later', (_) async {}, (_) async {});
          final migrator = Migrator(
            db,
            table: history,
            migrations: [migration, later],
          );
          final skipped = <String>[];
          expect(
            await migrator.migrate(
              step: true,
              isolated: true,
              onSkipped: skipped.add,
            ),
            ['002_later'],
          );
          expect(skipped, ['001_conditional']);
          expect((await migrator.status()).map((s) => s.batch), [null, 1]);
          final queries = <LaconicQuery>[];
          await migrator.migrate(pretend: true, onQuery: queries.add);
          expect(evaluations, 1);
          expect(queries, hasLength(1));
          expect(await db.schema.hasTable(items), isFalse);
          enabled = true;
          expect(await migrator.migrate(isolated: true), ['001_conditional']);
          expect((await migrator.status()).map((s) => s.batch), [2, 1]);
          enabled = false;
          expect(await migrator.rollback(isolated: true), ['001_conditional']);
          expect(await db.schema.hasTable(items), isFalse);
        },
      );

      test(
        'named connections are cached and used for up, condition, preview and down',
        () async {
          final target = createDatabase();
          var resolutions = 0;
          var conditions = 0;
          addTearDown(target.close);
          final migration = TestMigration(
            '001_named',
            (connection) async {
              await connection.schema.create(items, (t) => t.integer('value'));
              await connection.table(items).insert([
                {'value': 9},
              ]);
            },
            (connection) => connection.schema.drop(items),
            connection: 'reporting',
            condition: (connection) {
              expect(connection, same(target));
              conditions++;
              return true;
            },
          );
          final migrator = Migrator(
            db,
            table: history,
            migrations: [migration],
            resolveConnection: (name) async {
              expect(name, 'reporting');
              resolutions++;
              return target;
            },
          );
          final queries = <LaconicQuery>[];
          await migrator.migrate(pretend: true, onQuery: queries.add);
          expect(queries.last.bindings, [9]);
          expect(conditions, 0);
          await migrator.migrate(isolated: true);
          expect(await target.table(items).value('value'), 9);
          expect((await migrator.status()).single.hasRun, isTrue);
          await migrator.rollback(isolated: true);
          expect(await target.schema.hasTable(items), isFalse);
          expect(resolutions, 1);
          expect(conditions, 1);
        },
      );

      test(
        'failed target work is not recorded and missing resolvers fail clearly',
        () async {
          final target = createDatabase();
          addTearDown(target.close);
          final migration = TestMigration(
            '001_failure',
            (connection) async {
              await connection.schema.create(items, (t) => t.id());
              throw StateError('target failed');
            },
            (_) async {},
            connection: 'remote',
          );
          await expectLater(
            Migrator(db, table: history, migrations: [migration]).migrate(),
            throwsA(
              isA<LaconicException>().having(
                (e) => e.toString(),
                'message',
                contains('No resolver'),
              ),
            ),
          );
          final migrator = Migrator(
            db,
            table: history,
            migrations: [migration],
            resolveConnection: (_) => target,
          );
          try {
            await expectLater(
              migrator.migrate(isolated: true),
              throwsA(isA<LaconicException>()),
            );
            expect((await migrator.status()).single.hasRun, isFalse);
            expect(
              await target.schema.hasTable(items),
              !target.grammar.supportsSchemaTransactions,
            );
          } finally {
            await target.schema.dropIfExists(items);
          }
        },
      );

      test(
        'isolation releases after success and errors and permits transactions and streams',
        () async {
          await db.withMigrationLock(() async {
            await db.schema.create(items, (t) => t.integer('value'));
            await db.transaction(
              () => db.table(items).insert([
                {'value': 3},
              ]),
            );
            expect(
              (await db.table(items).cursor().toList()).single['value'],
              3,
            );
            await expectLater(
              db.withMigrationLock(() async {}),
              throwsA(isA<LaconicException>()),
            );
          });
          await expectLater(
            db.withMigrationLock(() async {
              throw StateError('failure');
            }),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.withMigrationLock(() async => 42), 42);
          await db.transaction(() async {
            await expectLater(
              db.withMigrationLock(() async {}),
              throwsA(isA<LaconicException>()),
            );
            await expectLater(
              db.transaction(() async {}),
              throwsA(isA<LaconicException>()),
            );
          });
        },
      );
    });
  }

  /// Both factories must address the same physical database.
  static void registerContention(Laconic Function() createDatabase) {
    test(
      'migration locks exclude independent connections and skipped CLI succeeds',
      () async {
        final first = createDatabase();
        final second = createDatabase();
        try {
          await first.withMigrationLock(() async {
            await expectLater(
              second.withMigrationLock(() async => fail('must not enter')),
              throwsA(isA<MigrationLockException>()),
            );
            final output = StringBuffer();
            final error = StringBuffer();
            expect(
              await MigrationCli.runCommand(
                ['migrate', '--isolated'],
                createDatabase: createDatabase,
                migrations: () => [],
                output: output,
                errorOutput: error,
                environment: 'testing',
              ),
              0,
            );
            expect(output.toString(), contains('another migration'));
            expect(error.toString(), isEmpty);
          });
          expect(await second.withMigrationLock(() async => 7), 7);
        } finally {
          await first.close();
          await second.close();
        }
      },
    );
  }
}
