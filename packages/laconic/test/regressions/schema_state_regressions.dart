import 'dart:io';

import 'package:laconic/laconic.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'migrator_regressions.dart';

class SchemaTestDatabase {
  final Laconic database;
  final Future<void> Function() dispose;
  SchemaTestDatabase(this.database, this.dispose);
}

/// Uses matching server-image tools without requiring host MySQL/PG clients.
class DockerSchemaProcessRunner extends SchemaProcessRunner {
  final String container;
  final int port;
  const DockerSchemaProcessRunner(this.container, this.port);
  @override
  Future<void> run(
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
    String? inputPath,
    String? outputPath,
  }) => super.run(
    'docker',
    [
      'exec',
      '-i',
      for (final key in environment.keys) ...['-e', key],
      container,
      executable,
      for (final argument in arguments)
        argument.startsWith('--port=') ? '--port=$port' : argument,
    ],
    environment: environment,
    inputPath: inputPath,
    outputPath: outputPath,
  );
}

class FailingSchemaProcessRunner extends SchemaProcessRunner {
  @override
  Future<void> run(
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
    String? inputPath,
    String? outputPath,
  }) async => throw LaconicException('client failed');
}

abstract final class SchemaStateRegressions {
  static void register(
    Future<SchemaTestDatabase> Function() createDatabase, {
    SchemaProcessRunner? runner,
  }) {
    group('Native migration baselines', () {
      late SchemaTestDatabase fixture;
      late Laconic db;
      late Directory directory;
      late String path;
      setUp(() async {
        fixture = await createDatabase();
        db = fixture.database;
        directory = await Directory.systemTemp.createTemp('laconic_baseline_');
        path = p.join(directory.path, 'schema.sql');
      });
      tearDown(() async {
        await fixture.dispose();
        await directory.delete(recursive: true);
      });
      TestMigration initial() => TestMigration(
        '001_initial',
        (db) async {
          await db.schema.create('parents', (t) {
            t.id();
            t.string('title').defaultTo('untitled');
            t.unique(['title']);
          });
          await db.schema.create('children', (t) {
            t.id();
            t.foreignId('parent_id').constrained('parents');
            t.integer('amount');
            t.integer('doubled').storedAs('amount * 2').nullable();
            t.index(['amount']);
          });
        },
        (db) async {
          await db.schema.drop('children');
          await db.schema.drop('parents');
        },
      );
      TestMigration later() => TestMigration(
        '002_later',
        (db) => db.schema.create('later', (t) => t.id()),
        (db) => db.schema.drop('later'),
      );
      Migrator migrator(
        List<Migration> migrations, {
        SchemaProcessRunner? processRunner,
      }) => Migrator(
        db,
        migrations: migrations,
        schemaPath: path,
        schemaProcessRunner: processRunner ?? runner,
      );

      test(
        'native schema, constraints, generated columns, views and history survive restore without user data',
        () async {
          await migrator([initial()]).migrate();
          await db.statement(
            'create view parent_titles as select title from parents',
          );
          await db.table('parents').insert([
            {'title': 'private data'},
          ]);
          await migrator([initial()]).dumpSchema(path);
          final sql = await File(path).readAsString();
          expect(sql, contains('001_initial'));
          expect(sql, isNot(contains('private data')));
          await db.statement('drop view parent_titles');
          await db.schema.dropAllTables();
          final restored = migrator([later()]);
          final loaded = <String>[];
          expect(
            await restored.migrate(isolated: true, onSchemaLoaded: loaded.add),
            ['002_later'],
          );
          expect(loaded, [path]);
          expect(await db.table('parents').count(), 0);
          expect(
            (await db.schema.getViews()).map((v) => v.name),
            contains('parent_titles'),
          );
          expect((await restored.status()).map((s) => s.batch), [1, 2]);
          expect((await restored.status()).first.baseline, isTrue);
          expect((await restored.status()).first.missing, isFalse);
          final parent = await db.table('parents').insertGetId({
            'title': 'restored',
          });
          await db.table('children').insert([
            {'parent_id': parent, 'amount': 6},
          ]);
          expect(await db.table('children').value('doubled'), 12);
          expect(
            await db.schema.hasIndex('parents', ['title'], type: 'unique'),
            isTrue,
          );
          expect(await db.schema.hasIndex('children', ['amount']), isTrue);
          expect(await db.schema.getForeignKeys('children'), hasLength(1));
          await expectLater(
            db.table('parents').insert([
              {'title': 'restored'},
            ]),
            throwsA(isA<LaconicException>()),
          );
          expect(await restored.migrate(), isEmpty);
          await restored.dumpSchema(
            path,
          ); // Can re-dump previously pruned history.
          await expectLater(restored.reset(), throwsA(isA<LaconicException>()));
          expect(
            await db.schema.hasTable('later'),
            isTrue,
          ); // All definitions validated first.
        },
      );

      test(
        'preview reads baseline and pending SQL without importing, fresh and step resume batches',
        () async {
          await migrator([initial()]).migrate();
          await migrator([initial()]).dumpSchema(path);
          await db.schema.dropAllTables();
          final restored = migrator([later()]);
          final queries = <LaconicQuery>[];
          expect(await restored.migrate(pretend: true, onQuery: queries.add), [
            '002_later',
          ]);
          expect(queries, hasLength(2));
          expect(queries.first.sql, contains('-- Laconic schema v1'));
          expect(await db.schema.getTables(), isEmpty);
          expect(await restored.fresh(step: true, isolated: true), [
            '002_later',
          ]);
          expect((await restored.status()).map((s) => s.batch), [1, 2]);
          expect(await restored.rollback(), ['002_later']);
          expect(await db.schema.hasTable('parents'), isTrue);
        },
      );

      test(
        'nonempty schemas and incompatible manifests are rejected before import',
        () async {
          await migrator([initial()]).migrate();
          await migrator([initial()]).dumpSchema(path);
          await db.schema.drop('migrations');
          await expectLater(
            migrator([]).migrate(),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.hasTable('parents'), isTrue);
          await db.schema.dropAllTables();
          final source = await File(path).readAsString();
          await File(path).writeAsString(
            source.replaceFirst('"table":"migrations"', '"table":"wrong"'),
          );
          await expectLater(
            migrator([]).migrate(),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.schema.getTables(), isEmpty);
        },
      );

      test(
        'failed dump keeps prior baseline and never invokes prune callback',
        () async {
          await migrator([initial()]).migrate();
          await migrator([initial()]).dumpSchema(path);
          final prior = await File(path).readAsString();
          var pruned = false;
          await expectLater(
            migrator([
              initial(),
            ], processRunner: FailingSchemaProcessRunner()).dumpSchema(
              path,
              onDumped: (_) {
                pruned = true;
              },
            ),
            throwsA(isA<LaconicException>()),
          );
          expect(pruned, isFalse);
          expect(await File(path).readAsString(), prior);
          expect(directory.listSync(), hasLength(1));
        },
      );

      test(
        'named migrations use a separate physical database and cannot be squashed together',
        () async {
          final remote = await createDatabase();
          try {
            final migration = TestMigration(
              '001_remote',
              (target) => target.schema.create('remote_items', (t) => t.id()),
              (target) => target.schema.drop('remote_items'),
              connection: 'remote',
            );
            final deployment = Migrator(
              db,
              migrations: [migration],
              schemaProcessRunner: runner,
              resolveConnection: (_) => remote.database,
            );
            await deployment.migrate(isolated: true);
            expect(await db.schema.hasTable('remote_items'), isFalse);
            expect(
              await remote.database.schema.hasTable('remote_items'),
              isTrue,
            );
            expect(
              await remote.database.schema.hasTable('migrations'),
              isFalse,
            );
            await expectLater(
              deployment.dumpSchema(path),
              throwsA(isA<LaconicException>()),
            );
            expect(await File(path).exists(), isFalse);
            await deployment.rollback(isolated: true);
            expect(
              await remote.database.schema.hasTable('remote_items'),
              isFalse,
            );
          } finally {
            await remote.dispose();
          }
        },
      );
    });
  }
}
