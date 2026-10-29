import 'dart:io';

import 'package:laconic/laconic.dart';
import 'package:laconic/src/cli/migration_generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

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

  Future<int> cli(List<String> args) => MigrationCli.run(
    args,
    workingDirectory: temporary,
    output: output,
    errorOutput: errors,
  );

  test(
    'help and usage errors have distinct streams and do not need config',
    () async {
      expect(await cli(['--help']), 0);
      expect(output.toString(), contains('make'));
      expect(errors.toString(), isEmpty);
      output.clear();
      expect(await cli([]), 64);
      expect(output.toString(), isEmpty);
      expect(errors.toString(), contains('Provide a command'));
      errors.clear();
      expect(await cli(['migrate', '--unknown']), 64);
      expect(output.toString(), isEmpty);
      expect(errors.toString(), contains('Usage:'));
      errors.clear();
      expect(await cli(['rollback', '--step=0']), 64);
      expect(errors.toString(), contains('positive integer'));
      expect(temporary.listSync(), isEmpty);
    },
  );

  test(
    'make generates a migration with a valid stable name and public class',
    () async {
      expect(
        await cli([
          '--path',
          'custom migrations',
          'make',
          'create_items',
          '--create=items',
        ]),
        0,
      );
      final files =
          Directory(
            p.join(temporary.path, 'custom migrations'),
          ).listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      final source = await files.single.readAsString();
      expect(
        p.basename(files.single.path),
        matches(r'^\d{20}_create_items\.dart$'),
      );
      expect(source, contains('class DatabaseMigration extends Migration'));
      expect(source, contains(p.basenameWithoutExtension(files.single.path)));
      expect(source, contains('database.schema.create("items"'));
      expect(source, contains('database.schema.drop("items")'));
      expect(errors.toString(), isEmpty);
    },
  );

  test(
    'make rejects traversal, invalid identifiers, and missing names',
    () async {
      for (final args in [
        ['make', '../escape'],
        ['make'],
        ['make', 'a', 'b'],
        ['make', 'create_items', '--create=items; drop table users'],
      ]) {
        expect(await cli(args), 64);
      }
      expect(temporary.listSync(), isEmpty);
      expect(output.toString(), isEmpty);
    },
  );

  test('generation never overwrites an existing migration', () async {
    final stamp = DateTime.utc(2026, 10, 29, 10, 11, 12, 123, 456);
    final file = await MigrationGenerator.generate(
      directory: temporary,
      name: 'custom_change',
      timestamp: stamp,
    );
    expect(p.basename(file.path), '20261029101112123456_custom_change.dart');
    final original = await file.readAsString();
    expect(original, contains('UnimplementedError'));
    await expectLater(
      MigrationGenerator.generate(
        directory: temporary,
        name: 'custom_change',
        timestamp: stamp,
      ),
      throwsException,
    );
    expect(await file.readAsString(), original);
  });

  test('configuration and missing directory errors are actionable', () async {
    expect(await cli(['status']), 78);
    expect(errors.toString(), contains('createDatabase()'));
    final config = File(p.join(temporary.path, 'database', 'migrations.dart'));
    await config.parent.create(recursive: true);
    await config.writeAsString('');
    errors.clear();
    expect(await cli(['status']), 78);
    expect(errors.toString(), contains('Missing migrations directory'));
    expect(output.toString(), isEmpty);
  });
}
