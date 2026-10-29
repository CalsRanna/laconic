import 'dart:async';

import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

class TestMigration extends Migration {
  @override
  final String name;
  final Future<void> Function(Laconic) apply;
  final Future<void> Function(Laconic) revert;
  @override
  final bool withinTransaction;

  TestMigration(
    this.name,
    this.apply,
    this.revert, {
    this.withinTransaction = true,
  });

  @override
  Future<void> up(Laconic database) => apply(database);
  @override
  Future<void> down(Laconic database) => revert(database);
}

abstract final class MigratorRegressions {
  static void register(
    Laconic Function() createDatabase, {
    Future<void> Function()? prepare,
  }) {
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

      setUpAll(() async {
        await prepare?.call();
      });
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
