import 'dart:convert';
import 'dart:io';

import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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
    'database commands run, print JSON status, roll back, and close each connection',
    () async {
      var opened = 0;
      var closed = 0;
      Future<int> run(List<String> args) => runMigrationCommand(
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
    final code = await runMigrationCommand(
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
}
