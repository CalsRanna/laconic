import 'dart:async';

import 'package:laconic/laconic.dart';
import 'package:test/test.dart';
import 'migration_deployment_regressions.dart';

class TestMigration extends Migration {
  @override
  final String name;
  final Future<void> Function(Laconic) apply;
  final Future<void> Function(Laconic) revert;
  @override
  final bool withinTransaction;
  @override
  final String? connection;
  final FutureOr<bool> Function(Laconic)? condition;

  TestMigration(
    this.name,
    this.apply,
    this.revert, {
    this.withinTransaction = true,
    this.connection,
    this.condition,
  });

  @override
  FutureOr<bool> shouldRun(Laconic database) =>
      condition?.call(database) ?? true;

  @override
  Future<void> up(Laconic database) => apply(database);
  @override
  Future<void> down(Laconic database) => revert(database);
}

abstract final class MigratorRegressions {
  static void register(
    Laconic Function() createDatabase, {
    Future<void> Function()? prepare,
    String? namespaceType,
  }) {
    setUpAll(() async {
      await prepare?.call();
    });
    MigrationDeploymentRegressions.register(createDatabase);
    group('Migrator', () {
      const history = 'laconic_migration_history';
      const users = 'laconic_migration_users';
      const posts = 'laconic_migration_posts';
      late Laconic db;

      TestMigration create(String name, String table) => TestMigration(
        name,
        (db) => db.schema.create(table, (table) => table.id()),
        (db) => db.schema.drop(table),
      );
      Migrator runner(List<Migration> migrations) =>
          Migrator(db, migrations: migrations, table: history);

      setUp(() async {
        db = createDatabase();
        for (final table in [posts, users, history]) {
          await db.schema.dropIfExists(table);
        }
      });
      tearDown(() async {
        try {
          for (final table in [posts, users, history]) {
            await db.schema.dropIfExists(table);
          }
        } finally {
          await db.close();
        }
      });

      if (namespaceType != null) {
        test(
          'fresh removes cycles in an isolated namespace and preserves other tables',
          () async {
            final namespace =
                'laconic_wipe_${DateTime.now().microsecondsSinceEpoch}';
            final quoted = db.grammar.quoteSchemaIdentifier(namespace);
            await db.statement('create $namespaceType $quoted');
            try {
              await db.schema.create(users, (t) => t.id());
              await db.schema.create('$namespace.a', (t) {
                t.id();
                t.bigInteger('b_id').nullable();
              });
              await db.schema.create('$namespace.b', (t) {
                t.id();
                t.bigInteger('a_id').nullable();
                t.foreign(['a_id']).references(['id']).on('$namespace.a');
              });
              await db.schema.table(
                '$namespace.a',
                (t) =>
                    t.foreign(['b_id']).references(['id']).on('$namespace.b'),
              );
              final a = await db.table('$namespace.a').insertGetId({
                'b_id': null,
              });
              final b = await db.table('$namespace.b').insertGetId({'a_id': a});
              await db.table('$namespace.a').where('id', a).update({'b_id': b});
              final migration = create('001_items', '$namespace.items');
              final migrator = Migrator(
                db,
                migrations: [migration],
                table: '$namespace.history',
              );
              await migrator.migrate();
              expect(await migrator.fresh(), [migration.name]);
              expect(
                (await db.schema.getTables(
                  schema: namespace,
                )).map((t) => t.name).toSet(),
                {'items', 'history'},
              );
              expect(await db.schema.hasTable(users), isTrue);
              expect((await migrator.status()).single.batch, 1);
            } finally {
              await db.schema.dropAllTables(schema: namespace);
              await db.statement('drop $namespaceType $quoted');
            }
          },
        );
      }

      test(
        'status is read-only and migrate orders names and skips applied work',
        () async {
          final first = create('20261029_001_users', users);
          final second = create('20261029_002_posts', posts);
          final migrator = runner([second, first]);
          expect((await migrator.status()).map((s) => s.name), [
            first.name,
            second.name,
          ]);
          expect(await db.schema.hasTable(history), isFalse);
          expect(await migrator.migrate(), [first.name, second.name]);
          expect(await migrator.migrate(), isEmpty);
          expect((await migrator.status()).map((s) => s.batch), [1, 1]);
          expect(await migrator.rollback(), [second.name, first.name]);
          expect(await db.schema.hasTable(users), isFalse);
          expect(await db.schema.hasTable(posts), isFalse);
          expect((await migrator.status()).every((s) => !s.hasRun), isTrue);
        },
      );

      test('separate runs and step mode produce rollback batches', () async {
        final first = create('001_users', users);
        final second = create('002_posts', posts);
        await runner([first]).migrate();
        final migrator = runner([first, second]);
        await migrator.migrate();
        expect((await migrator.status()).map((s) => s.batch), [1, 2]);
        expect(await migrator.rollback(), [second.name]);
        expect(await db.schema.hasTable(users), isTrue);
        await migrator.reset();
        await migrator.migrate(step: true);
        expect((await migrator.status()).map((s) => s.batch), [1, 2]);
        expect(await migrator.rollback(steps: 2), [second.name, first.name]);
      });

      test(
        'batch selection and refresh preserve execution and history order',
        () async {
          final first = create('001_users', users);
          final second = create('002_posts', posts);
          final migrator = runner([first, second]);
          await migrator.migrate(step: true);
          expect(await migrator.rollback(batch: 1), [first.name]);
          expect((await migrator.status()).map((s) => s.batch), [null, 2]);
          expect(await migrator.rollback(batch: 99), isEmpty);
          final progress = <String>[];
          expect(
            await migrator.refresh(
              steps: 1,
              onRolledBack: (name) => progress.add('down:$name'),
              onApplied: (name) => progress.add('up:$name'),
            ),
            [first.name, second.name],
          );
          expect(progress, [
            'down:${second.name}',
            'up:${first.name}',
            'up:${second.name}',
          ]);
          expect((await migrator.status()).map((s) => s.batch), [1, 1]);
          expect(await migrator.refresh(), [first.name, second.name]);
        },
      );

      test(
        'preview captures bound SQL without writing schema or history',
        () async {
          final queries = <LaconicQuery>[];
          final migration = TestMigration('001_users', (db) async {
            await db.schema.create(users, (t) => t.integer('id'));
            await db.table(users).insert([
              {'id': 17},
            ]);
          }, (db) => db.schema.drop(users));
          final migrator = runner([migration]);
          expect(await migrator.migrate(pretend: true, onQuery: queries.add), [
            migration.name,
          ]);
          expect(queries, hasLength(2));
          expect(queries.last.bindings, [17]);
          expect(await db.schema.hasTable(users), isFalse);
          expect(await db.schema.hasTable(history), isFalse);
          await migrator.migrate();
          queries.clear();
          await migrator.rollback(pretend: true, onQuery: queries.add);
          expect(queries, hasLength(1));
          expect(await db.table(users).count(), 1);
          expect((await migrator.status()).single.hasRun, isTrue);
        },
      );

      test(
        'an up failure is not recorded and stops subsequent migrations',
        () async {
          final first = create('001_users', users);
          final failed = TestMigration('002_failure', (db) async {
            await db.schema.create(posts, (table) => table.id());
            throw StateError('up failed');
          }, (db) => db.schema.drop(posts));
          var laterRan = false;
          final later = TestMigration('003_later', (db) async {
            laterRan = true;
          }, (db) async {});
          final migrator = runner([first, failed, later]);
          await expectLater(migrator.migrate(), throwsA(anything));
          expect(laterRan, isFalse);
          expect((await migrator.status()).map((s) => s.hasRun), [
            true,
            false,
            false,
          ]);
          expect(await db.schema.hasTable(users), isTrue);
          expect(
            await db.schema.hasTable(posts),
            !db.grammar.supportsSchemaTransactions,
          );
          // A new operation can run after a failure releases the instance guard.
          expect(await migrator.rollback(), [first.name]);
        },
      );

      test(
        'a failed down retains history and rolls back transactional DDL',
        () async {
          final migration = TestMigration(
            '001_users',
            (db) => db.schema.create(users, (table) => table.id()),
            (db) async {
              await db.schema.drop(users);
              throw StateError('down failed');
            },
          );
          final migrator = runner([migration]);
          await migrator.migrate();
          await expectLater(migrator.rollback(), throwsA(anything));
          expect((await migrator.status()).single.hasRun, isTrue);
          expect(
            await db.schema.hasTable(users),
            db.grammar.supportsSchemaTransactions,
          );
        },
      );

      test(
        'missing definitions block the whole selected rollback before execution',
        () async {
          final first = create('001_users', users);
          final second = create('002_posts', posts);
          await runner([first, second]).migrate();
          final missing = runner([second]);
          expect((await missing.status()).first.missing, isTrue);
          await expectLater(
            missing.rollback(),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasTable(posts), isTrue);
          expect(await db.schema.hasTable(users), isTrue);
        },
      );

      test(
        'invalid registry names, duplicates, and rollback steps are rejected',
        () async {
          final first = create('001_users', users);
          expect(
            () => runner([first, first]),
            throwsA(isA<LaconicException>()),
          );
          expect(
            () => runner([first, create('001_USERS', posts)]),
            throwsA(isA<LaconicException>()),
          );
          expect(
            () => runner([create('bad name', users)]),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            runner([]).rollback(steps: 0),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            runner([]).rollback(batch: 0),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            runner([]).rollback(batch: 1, steps: 1),
            throwsA(isA<LaconicException>()),
          );
          await expectLater(
            runner([]).refresh(steps: 0),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasTable(history), isFalse);
        },
      );

      test('overlapping mutations on one instance are rejected', () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final migration = TestMigration('001_wait', (db) async {
          entered.complete();
          await release.future;
        }, (db) async {});
        final migrator = runner([migration]);
        final running = migrator.migrate();
        await entered.future;
        try {
          await expectLater(
            migrator.rollback(),
            throwsA(isA<LaconicException>()),
          );
        } finally {
          release.complete();
          await running;
        }
      });

      test('a migration can opt out of automatic transactions', () async {
        final migration = TestMigration(
          '001_nontransactional',
          (db) async {
            await db.schema.create(users, (table) => table.id());
            throw StateError('failed after DDL');
          },
          (db) => db.schema.drop(users),
          withinTransaction: false,
        );
        final migrator = runner([migration]);
        await expectLater(migrator.migrate(), throwsA(anything));
        expect(await db.schema.hasTable(users), isTrue);
        expect((await migrator.status()).single.hasRun, isFalse);
      });
    });
  }
}
