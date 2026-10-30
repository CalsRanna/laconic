import 'dart:io';
import 'dart:isolate';
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../../laconic/test/regressions/schema_state_regressions.dart';
import '../../laconic/test/regressions/migration_deployment_regressions.dart';

void main() {
  late Directory locks;
  setUpAll(() async {
    locks = await Directory.systemTemp.createTemp('laconic_locks_');
  });
  tearDownAll(() => locks.delete(recursive: true));
  MigrationDeploymentRegressions.registerContention(
    () => Laconic(SqliteDriver(SqliteConfig(p.join(locks.path, 'db.sqlite')))),
  );
  test(
    'SQLite lock coordinates independent Dart isolates and canonical file aliases',
    () async {
      final path = p.join(locks.path, 'isolate.sqlite');
      final db = Laconic(SqliteDriver(SqliteConfig(path)));
      try {
        await db.withMigrationLock(() async {
          expect(
            await Isolate.run(() async {
              final peer = Laconic(SqliteDriver(SqliteConfig(path)));
              try {
                await peer.withMigrationLock(() async {});
                return false;
              } on MigrationLockException {
                return true;
              } finally {
                await peer.close();
              }
            }),
            isTrue,
          );
          final alias = p.join(locks.path, 'alias.sqlite');
          await Link(alias).create(path);
          final peer = Laconic(SqliteDriver(SqliteConfig(alias)));
          try {
            await expectLater(
              peer.withMigrationLock(() async {}),
              throwsA(isA<MigrationLockException>()),
            );
          } finally {
            await peer.close();
          }
        });
      } finally {
        await db.close();
      }
    },
  );

  test(
    'SQLite baseline preserves FTS and triggers without shadow table rows',
    () async {
      final db = Laconic(
        SqliteDriver(SqliteConfig(p.join(locks.path, 'fts.sqlite'))),
      );
      final path = p.join(locks.path, 'fts.sql');
      try {
        await db.statement('create virtual table documents using fts5(body)');
        await db.schema.create('logs', (t) => t.string('body'));
        await db.statement(
          'create trigger add_document after insert on logs begin insert into documents(body) values (new.body); end',
        );
        await db.table('logs').insert([
          {'body': 'secret-old-row'},
        ]);
        final migrator = Migrator(db, migrations: [], schemaPath: path);
        await migrator.dumpSchema(path);
        final sql = await File(path).readAsString();
        expect(sql, isNot(contains('secret-old-row')));
        expect(sql, isNot(contains('CREATE TABLE "documents_data"')));
        await db.schema.dropAllTables();
        await migrator.migrate();
        expect(await db.table('documents').count(), 0);
        await db.table('logs').insert([
          {'body': 'restored searchable'},
        ]);
        expect(
          await db.table('documents').whereFullText([
            'body',
          ], 'searchable').count(),
          1,
        );
      } finally {
        await db.close();
      }
    },
  );

  SchemaStateRegressions.register(() async {
    final directory = await Directory.systemTemp.createTemp('laconic_dump_db_');
    final db = Laconic(
      SqliteDriver(SqliteConfig(p.join(directory.path, 'db.sqlite'))),
    );
    return SchemaTestDatabase(db, () async {
      await db.close();
      await directory.delete(recursive: true);
    });
  });
}
