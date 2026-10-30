import 'dart:convert';
import 'dart:io';

import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../../laconic/test/regressions/migrator_regressions.dart';
import '../../laconic/test/regressions/schema_state_regressions.dart';

class _CreateItems extends Migration {
  @override
  String get name => '001_create_items';
  @override
  Future<void> up(Laconic db) => db.schema.create('items', (t) => t.id());
  @override
  Future<void> down(Laconic db) => db.schema.drop('items');
}

class _TrackedDriver extends SqliteDriver {
  final void Function() onClose;
  _TrackedDriver(super.config, this.onClose);
  @override
  Future<void> close() async {
    await super.close();
    onClose();
  }
}

class _Migration extends Migration {
  @override
  final String name;
  final Future<void> Function(Laconic) apply;
  final Future<void> Function(Laconic) revert;

  _Migration(this.name, this.apply, this.revert);

  @override
  Future<void> up(Laconic db) => apply(db);
  @override
  Future<void> down(Laconic db) => revert(db);
}

void main() {
  late Directory temporary;
  late StringBuffer output;
  late StringBuffer errors;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('laconic_cli_');
    output = StringBuffer();
    errors = StringBuffer();
  });
  tearDown(() => temporary.delete(recursive: true));

  test(
    'named CLI connections are cached and all opened connections close even on resolver failure',
    () async {
      var defaults = 0;
      final opened = <String>[];
      final closed = <String>[];
      final first = TestMigration(
        '001_named',
        (_) async {},
        (_) async {},
        connection: 'reporting',
      );
      final second = TestMigration(
        '002_other',
        (_) async {},
        (_) async {},
        connection: 'missing',
      );
      final code = await MigrationCli.runCommand(
        ['migrate', '--database=reporting', '--isolated'],
        createDatabase: () {
          defaults++;
          throw StateError('unexpected default');
        },
        resolveConnection: (name) {
          opened.add(name);
          if (name == 'missing') throw StateError('missing config');
          return Laconic(
            _TrackedDriver(
              SqliteConfig(p.join(temporary.path, '$name.db')),
              () => closed.add(name),
            ),
          );
        },
        migrations: () => [first, second],
        output: output,
        errorOutput: errors,
        environment: 'testing',
      );
      expect(code, 70);
      expect(defaults, 0);
      expect(opened, ['reporting', 'missing']);
      expect(closed, ['reporting']);
      expect(output.toString(), contains('Migrated: 001_named'));
      expect(errors.toString(), contains('missing config'));
    },
  );

  test(
    'prune retains skipped sources and a failed dump never removes sources',
    () async {
      final applied = TestMigration(
        '001_applied',
        (db) => db.schema.create('items', (t) => t.id()),
        (db) => db.schema.drop('items'),
      );
      final skipped = TestMigration(
        '002_skipped',
        (_) async {},
        (_) async {},
        condition: (_) => false,
      );
      final files = <String, String>{};
      for (final migration in [applied, skipped]) {
        final path = p.join(temporary.path, '${migration.name}.dart');
        await File(path).writeAsString('source');
        files[migration.name] = path;
      }
      Future<int> run(List<String> arguments, {SchemaProcessRunner? runner}) =>
          MigrationCli.runCommand(
            arguments,
            createDatabase:
                () => Laconic(
                  SqliteDriver(
                    SqliteConfig(p.join(temporary.path, 'database.db')),
                  ),
                ),
            migrations: () => [applied, skipped],
            schemaPath: p.join(temporary.path, 'baseline.sql'),
            migrationFiles: files,
            schemaProcessRunner: runner,
            output: output,
            errorOutput: errors,
            environment: 'testing',
          );
      expect(await run(['migrate']), 0);
      expect(
        await run([
          'schema:dump',
          '--prune',
        ], runner: FailingSchemaProcessRunner()),
        70,
      );
      expect(files.values.every((path) => File(path).existsSync()), isTrue);
      errors.clear();
      expect(await run(['schema:dump', '--prune']), 0);
      expect(File(files[applied.name]!).existsSync(), isFalse);
      expect(File(files[skipped.name]!).existsSync(), isTrue);
      expect(errors.toString(), isEmpty);
    },
  );

  test(
    'database commands run, print JSON status, roll back, and close each connection',
    () async {
      var opened = 0;
      var closed = 0;
      Future<int> run(List<String> args) => MigrationCli.runCommand(
        args,
        createDatabase: () {
          opened++;
          return Laconic(
            _TrackedDriver(
              SqliteConfig(p.join(temporary.path, 'data.db')),
              () => closed++,
            ),
          );
        },
        migrations: () => [_CreateItems()],
        output: output,
        errorOutput: errors,
      );
      expect(await run(['status', '--help']), 0);
      expect(await run(['rollback', '--step=-1']), 64);
      expect(opened, 0);
      output.clear();
      errors.clear();
      expect(await run(['status', '--json']), 0);
      expect(
        (jsonDecode(output.toString()) as List).single['status'],
        'pending',
      );
      output.clear();
      expect(await run(['migrate', '--step']), 0);
      expect(output.toString(), contains('Migrated: 001_create_items'));
      output.clear();
      expect(await run(['migrate:status', '--json']), 0);
      expect((jsonDecode(output.toString()) as List).single['batch'], 1);
      output.clear();
      expect(await run(['migrate:rollback', '--step=1']), 0);
      expect(output.toString(), contains('Rolled back:'));
      expect(closed, opened);
      expect(errors.toString(), isEmpty);
    },
  );

  test('execution errors return nonzero and close the database', () async {
    var closed = false;
    final code = await MigrationCli.runCommand(
      ['rollback'],
      createDatabase:
          () => Laconic(
            _TrackedDriver(SqliteConfig(':memory:'), () => closed = true),
          ),
      migrations: () => [_CreateItems(), _CreateItems()],
      output: output,
      errorOutput: errors,
    );
    expect(code, 70);
    expect(closed, isTrue);
    expect(output.toString(), isEmpty);
    expect(errors.toString(), contains('Duplicate migration'));
  });

  test(
    'fresh handles cyclic foreign keys and removes untracked tables',
    () async {
      final path = p.join(temporary.path, 'fresh.db');
      final db = Laconic(SqliteDriver(SqliteConfig(path)));
      await db.statement('pragma foreign_keys = on');
      await db.statement(
        'create table a (id integer primary key, b_id integer references b(id))',
      );
      await db.statement(
        'create table b (id integer primary key, a_id integer references a(id))',
      );
      await db.statement('insert into a values (1, null)');
      await db.statement('insert into b values (1, 1)');
      await db.statement('update a set b_id = 1');
      await db.statement('create virtual table search using fts5(content)');
      await db.statement("insert into search values ('text')");
      await db.statement('create view retained_view as select 1 as n');
      final first = _CreateItems();
      final migrator = Migrator(db, migrations: [first]);
      await migrator.migrate();
      await db.table('items').insert([
        {'id': 123},
      ]);
      await db.close();
      expect(
        await MigrationCli.runCommand(
          ['migrate:fresh', '--step'],
          createDatabase: () => Laconic(SqliteDriver(SqliteConfig(path))),
          migrations: () => [first],
          output: output,
          errorOutput: errors,
        ),
        0,
        reason: errors.toString(),
      );
      final check = Laconic(SqliteDriver(SqliteConfig(path)));
      try {
        expect((await check.schema.getTables()).map((t) => t.name).toSet(), {
          'items',
          'migrations',
        });
        expect(await check.table('items').count(), 0);
        expect((await check.schema.getViews()).single.name, 'retained_view');
        expect(
          (await Migrator(check, migrations: [first]).status()).single.batch,
          1,
        );
      } finally {
        await check.close();
      }
      expect(output.toString(), contains('Dropped all tables.'));
    },
  );

  test('wipe restores foreign keys and rolls back a failed drop', () async {
    var fail = false;
    final db = Laconic(
      SqliteDriver(SqliteConfig(':memory:')),
      beforeQuery: (query) {
        if (fail &&
            query.sql.startsWith('drop table') &&
            query.sql.contains('"b"')) {
          throw StateError('drop blocked');
        }
      },
    );
    try {
      await db.statement('pragma foreign_keys = on');
      await db.schema.create('a', (t) => t.id());
      await db.schema.create('b', (t) => t.id());
      fail = true;
      await expectLater(db.schema.dropAllTables(), throwsA(anything));
      expect((await db.schema.getTables()).map((t) => t.name), ['a', 'b']);
      expect(
        (await db.select('pragma foreign_keys')).single['foreign_keys'],
        1,
      );
      fail = false;
      await db.schema.dropAllTables();
      expect(await db.schema.getTables(), isEmpty);
      expect(
        (await db.select('pragma foreign_keys')).single['foreign_keys'],
        1,
      );
    } finally {
      await db.close();
    }
  });

  test(
    'fresh uses the qualified history schema and preserves other schemas',
    () async {
      final db = Laconic(SqliteDriver(SqliteConfig(':memory:')));
      try {
        await db.statement("attach ':memory:' as app");
        await db.schema.create('keep', (t) => t.id());
        await db.schema.create('app.orphan', (t) => t.id());
        final migrator = Migrator(
          db,
          migrations: [
            _Migration(
              '001_create',
              (db) => db.schema.create('app.items', (t) => t.id()),
              (db) => db.schema.drop('app.items'),
            ),
          ],
          table: 'app.history',
        );
        await migrator.fresh();
        expect(await db.schema.hasTable('keep'), isTrue);
        expect(await db.schema.hasTable('app.orphan'), isFalse);
        expect((await db.schema.getTables(schema: 'app')).map((t) => t.name), [
          'history',
          'items',
        ]);
      } finally {
        await db.close();
      }
    },
  );

  test(
    'preview reads existing metadata for change but suppresses every write route',
    () async {
      final path = p.join(temporary.path, 'preview.db');
      final setup = Laconic(SqliteDriver(SqliteConfig(path)));
      await setup.schema.create('items', (t) {
        t.id();
        t.string('title');
      });
      await setup.table('items').insert([
        {'title': 'original'},
      ]);
      await setup.close();
      final commands = <LaconicQuery>[];
      final change = _Migration('001_change', (db) async {
        await db.schema.table(
          'items',
          (t) => t.text('title').nullable().change(),
        );
        await db.transaction(() async {
          expect(await db.select("delete from items returning *"), isEmpty);
          expect(
            await db.selectStream('select * from items').toList(),
            isEmpty,
          );
          expect(
            await db.insertAndGetId("insert into items(title) values (?)", [
              'hidden',
            ]),
            0,
          );
          expect(await db.affectingStatement('delete from items'), 0);
          await db.statement('drop table items');
        });
      }, (db) async {});
      expect(
        await MigrationCli.runCommand(
          ['migrate', '--pretend'],
          createDatabase:
              () => Laconic(
                SqliteDriver(SqliteConfig(path)),
                beforeQuery: commands.add,
              ),
          migrations: () => [change],
          output: output,
          errorOutput: errors,
        ),
        0,
        reason: errors.toString(),
      );
      expect(output.toString(), contains('Would migrate: 001_change'));
      expect(output.toString(), contains('Bindings: ["hidden"]'));
      expect(commands.every((q) => q.sql.startsWith('select')), isTrue);
      final check = Laconic(SqliteDriver(SqliteConfig(path)));
      try {
        expect(await check.table('items').value('title'), 'original');
        expect((await check.schema.getColumns('items')).last.nullable, isFalse);
        expect(await check.schema.hasTable('migrations'), isFalse);
      } finally {
        await check.close();
      }
    },
  );

  test(
    'refresh reports completed rollback and stops before up on failure',
    () async {
      final path = p.join(temporary.path, 'failed_refresh.db');
      final first = _Migration(
        '001_first',
        (db) async {},
        (db) async => throw StateError('cannot reverse'),
      );
      final second = _Migration('002_second', (db) async {}, (db) async {});
      final setup = Laconic(SqliteDriver(SqliteConfig(path)));
      await Migrator(setup, migrations: [first, second]).migrate();
      await setup.close();
      expect(
        await MigrationCli.runCommand(
          ['refresh'],
          createDatabase: () => Laconic(SqliteDriver(SqliteConfig(path))),
          migrations: () => [first, second],
          output: output,
          errorOutput: errors,
        ),
        70,
      );
      expect(output.toString(), 'Rolled back: 002_second\n');
      expect(errors.toString(), contains('001_first (down) failed'));
      final check = Laconic(SqliteDriver(SqliteConfig(path)));
      try {
        expect(
          (await Migrator(check, migrations: [first, second]).status()).map(
            (s) => s.hasRun,
          ),
          [true, false],
        );
      } finally {
        await check.close();
      }
    },
  );

  test(
    'force authorizes production writes while previews remain read-only',
    () async {
      final path = p.join(temporary.path, 'production.db');
      Future<int> run(List<String> args) => MigrationCli.runCommand(
        args,
        createDatabase: () => Laconic(SqliteDriver(SqliteConfig(path))),
        migrations: () => [_CreateItems()],
        environment: 'production',
        output: output,
        errorOutput: errors,
      );
      expect(await run(['migrate']), 78);
      expect(File(path).existsSync(), isFalse);
      expect(await run(['migrate', '--pretend']), 0);
      expect(await run(['migrate', '--force']), 0);
      expect(await run(['reset', '--pretend']), 0);
      output.clear();
      expect(await run(['status', '--json']), 0);
      expect(
        (jsonDecode(output.toString()) as List).single['status'],
        'applied',
      );
      expect(await run(['reset', '--force']), 0);
    },
  );
}
