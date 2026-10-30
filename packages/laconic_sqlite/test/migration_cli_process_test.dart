@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_process/test_process.dart';

void main() {
  late String packageRoot;
  late String executable;
  late Directory project;
  final dart = cli_util.dartExecutable!;

  setUpAll(() async {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:laconic/laconic.dart'),
    );
    executable = p.join(
      p.dirname(p.dirname(File.fromUri(library!).path)),
      'bin',
      'laconic.dart',
    );
    final driver = await Isolate.resolvePackageUri(
      Uri.parse('package:laconic_sqlite/laconic_sqlite.dart'),
    );
    packageRoot = p.dirname(p.dirname(File.fromUri(driver!).path));
  });
  setUp(() async {
    final cache = Directory(p.join(packageRoot, '.dart_tool'));
    await cache.create(recursive: true);
    project = await cache.createTemp("cli project's \$ test_");
    await File(p.join(project.path, 'pubspec.yaml')).writeAsString('''
name: migration_cli_fixture
environment:
  sdk: '>=3.7.0 <4.0.0'
dependencies:
  laconic: ^6.0.0
  laconic_sqlite:
    path: ${jsonEncode(packageRoot)}
dependency_overrides:
  laconic:
    path: ${jsonEncode(p.dirname(p.dirname(executable)))}
''');
    final install = await TestProcess.start(dart, [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: project.path);
    await install.shouldExit(0);
    final config = File(p.join(project.path, 'database', 'migrations.dart'));
    await config.parent.create(recursive: true);
    await config.writeAsString('''import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

abstract final class DatabaseConfiguration {
  static Laconic createDatabase() => Laconic(SqliteDriver(SqliteConfig('test.db')));
}
''');
  });
  tearDown(() => project.delete(recursive: true));

  Future<({int code, String output, String error})> run(
    List<String> arguments, {
    String? binary,
    int? expected = 0,
    String environment = 'testing',
  }) async {
    final process = await TestProcess.start(
      binary ?? dart,
      binary == null
          ? ['run', '--verbosity=error', 'laconic', ...arguments]
          : arguments,
      workingDirectory: project.path,
      environment: {'DART_SDK': cli_util.sdkPath!, 'APP_ENV': environment},
    );
    final out = process.stdoutStream().join('\n');
    final err = process.stderrStream().join('\n');
    await process.shouldExit(expected);
    return (code: await process.exitCode, output: await out, error: await err);
  }

  test(
    'generated files migrate, report JSON status, and roll back by batch or step',
    () async {
      final configuration =
          jsonDecode(
                await File(
                  p.join(project.path, '.dart_tool', 'package_config.json'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      final packages = (configuration['packages'] as List).map(
        (entry) => entry['name'] as String,
      );
      expect(packages, contains('laconic'));
      expect(packages.where((name) => name.startsWith('laconic_')), [
        'laconic_sqlite',
      ]);
      final made = await run(['make', 'create_items', '--create=items']);
      expect(made.output, contains('Created:'));
      final pending =
          jsonDecode((await run(['status', '--json'])).output) as List;
      expect(pending.single['status'], 'pending');
      expect((await run(['migrate'])).output, contains('Migrated:'));
      expect((await run(['migrate'])).output, 'No pending migrations.');
      await run(['make:migration', 'create_posts', '--create=posts']);
      await run(['migrate', '--step']);
      final applied =
          jsonDecode((await run(['migrate:status', '--json'])).output) as List;
      expect(applied.map((s) => s['batch']), [1, 2]);
      await run(['rollback', '--step=1']);
      final states =
          jsonDecode((await run(['status', '--json'])).output) as List;
      expect(states.map((s) => s['status']), ['applied', 'pending']);
      await run(['migrate:rollback']);
      expect((await run(['rollback'])).output, 'Nothing to roll back.');
      expect(
        Directory(p.join(project.path, '.dart_tool', 'laconic')).listSync(),
        isEmpty,
      );
    },
    timeout: Timeout(Duration(minutes: 3)),
  );

  test(
    'syntax errors propagate nonzero and clean up the temporary registry',
    () async {
      await run(['make', 'bad_migration']);
      final file =
          Directory(
            p.join(project.path, 'database', 'migrations'),
          ).listSync().whereType<File>().single;
      await file.writeAsString('this is invalid Dart');
      final result = await run(['migrate'], expected: null);
      expect(result.code, isNot(0));
      expect(result.error, contains('Error'));
      expect(File(p.join(project.path, 'test.db')).existsSync(), isFalse);
      expect(
        Directory(p.join(project.path, '.dart_tool', 'laconic')).listSync(),
        isEmpty,
      );
    },
  );

  test(
    'lifecycle aliases, previews, local options and production force survive the launcher',
    () async {
      await run(['make', 'create_items', '--create=items', '--path=changes']);
      await run(['make', 'create_posts', '--create=posts', '--path=changes']);
      Future<({int code, String output, String error})> command(
        List<String> args, {
        int expected = 0,
        String environment = 'testing',
      }) => run(
        [...args, '--path=changes', '--table=custom_history'],
        expected: expected,
        environment: environment,
      );
      final blocked = await command(
        ['migrate'],
        environment: 'production',
        expected: 78,
      );
      expect(blocked.error, contains('--force'));
      expect(File(p.join(project.path, 'test.db')).existsSync(), isFalse);
      final preview = await command([
        'migrate',
        '--pretend',
      ], environment: 'production');
      expect(preview.output, contains('SQL: create table'));
      expect(preview.output, contains('Would migrate:'));
      await command([
        'migrate',
        '--force',
        '--step',
      ], environment: 'production');
      await command(['migrate:rollback', '--batch=2', '--pretend']);
      final applied =
          jsonDecode((await command(['status', '--json'])).output) as List;
      expect(applied.map((s) => s['batch']), [1, 2]);
      await command(['migrate:refresh', '--step=1']);
      final refreshed =
          jsonDecode((await command(['status', '--json'])).output) as List;
      expect(refreshed.map((s) => s['batch']), [1, 2]);
      await command(['migrate:reset']);
      final pending =
          jsonDecode((await command(['status', '--json'])).output) as List;
      expect(pending.every((s) => s['status'] == 'pending'), isTrue);
      await command(['migrate']);
      final db = Laconic(
        SqliteDriver(SqliteConfig(p.join(project.path, 'test.db'))),
      );
      await db.schema.create('untracked', (t) => t.id());
      await db.close();
      expect(
        (await command(['migrate:fresh', '--step'])).output,
        contains('Dropped all tables.'),
      );
      final check = Laconic(
        SqliteDriver(SqliteConfig(p.join(project.path, 'test.db'))),
      );
      try {
        expect(await check.schema.hasTable('untracked'), isFalse);
        expect((await check.schema.getTables()).map((t) => t.name).toSet(), {
          'items',
          'posts',
          'custom_history',
        });
      } finally {
        await check.close();
      }
      expect(
        Directory(p.join(project.path, '.dart_tool', 'laconic')).listSync(),
        isEmpty,
      );
    },
  );

  test('an unimplemented migration fails without recording success', () async {
    await run(['make', 'custom_change']);
    final result = await run(['migrate'], expected: 70);
    expect(result.error, contains('Implement up()'));
    final states = jsonDecode((await run(['status', '--json'])).output) as List;
    expect(states.single['status'], 'pending');
  });

  test('a missing applied file is visible and prevents rollback', () async {
    await run(['make', 'create_items', '--create=items']);
    await run(['migrate']);
    final file =
        Directory(
          p.join(project.path, 'database', 'migrations'),
        ).listSync().whereType<File>().single;
    await file.delete();
    final states = jsonDecode((await run(['status', '--json'])).output) as List;
    expect(states.single['missing'], isTrue);
    final result = await run(['rollback'], expected: 70);
    expect(result.error, contains('Missing migration definition'));
  });

  test(
    'custom paths and history table work, and filename mismatches fail before connection',
    () async {
      final config = File(p.join(project.path, 'database', 'migrations.dart'));
      final customConfig = await config.rename(
        p.join(project.path, 'custom config.dart'),
      );
      final changes = p.join(project.path, 'custom changes');
      final options = [
        '--config',
        customConfig.path,
        '--path',
        changes,
        '--table',
        'custom_history',
      ];
      await run([...options, 'make', 'create_items', '--create=items']);
      final file = Directory(changes).listSync().whereType<File>().single;
      final source = await file.readAsString();
      await file.writeAsString(
        source.replaceFirst(
          p.basenameWithoutExtension(file.path),
          '001_wrong_name',
        ),
      );
      final failure = await run([...options, 'status'], expected: 65);
      expect(failure.error, contains('must match its filename'));
      expect(File(p.join(project.path, 'test.db')).existsSync(), isFalse);
      await file.writeAsString(source);
      await run([...options, 'migrate']);
      final db = Laconic(
        SqliteDriver(SqliteConfig(p.join(project.path, 'test.db'))),
      );
      try {
        expect(await db.schema.hasTable('custom_history'), isTrue);
        expect(await db.schema.hasTable('migrations'), isFalse);
      } finally {
        await db.close();
      }
      await run([...options, 'rollback']);
    },
  );

  test(
    'native CLI discovers the SDK instead of recursively invoking itself',
    () async {
      final binary = p.join(
        project.path,
        Platform.isWindows ? 'migrations.exe' : 'migrations',
      );
      final compile = await TestProcess.start(dart, [
        'compile',
        'exe',
        executable,
        '-o',
        binary,
      ], workingDirectory: packageRoot);
      await compile.shouldExit(0);
      await run([
        'make',
        'create_native_items',
        '--create=native_items',
      ], binary: binary);
      await run(['migrate'], binary: binary);
      final states =
          jsonDecode((await run(['status', '--json'], binary: binary)).output)
              as List;
      expect(states.single['status'], 'applied');
      await run(['rollback'], binary: binary);
    },
    timeout: Timeout(Duration(minutes: 3)),
  );
}
