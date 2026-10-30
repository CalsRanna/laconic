import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cli_util/cli_util.dart' as cli_util;
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

import 'cli_exception.dart';
import 'dart_source.dart';

abstract final class MigrationProject {
  static Future<int> run({
    required Directory project,
    required String configPath,
    required String migrationsPath,
    required String table,
    required List<String> arguments,
    required StringSink output,
    required StringSink errorOutput,
    String? database,
  }) async {
    final config = File(p.normalize(p.join(project.path, configPath)));
    final directory = Directory(
      p.normalize(p.join(project.path, migrationsPath)),
    );
    if (!await config.exists()) {
      throw MigrationCliException(
        'Missing database configuration: ${config.path}\n'
        'Create a Dart file exporting DatabaseConfiguration with a static createDatabase() method that returns a Laconic instance.',
        ExitCode.config.code,
      );
    }
    if (!await directory.exists()) {
      throw MigrationCliException(
        'Missing migrations directory: ${directory.path}\n'
        'Generate a migration with the make command, or create an empty directory.',
        ExitCode.config.code,
      );
    }
    final files = <File>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (p.extension(entity.path) != '.dart') continue;
      if (entity is! File) {
        throw MigrationCliException(
          'Migration must be a regular Dart file: ${entity.path}',
          ExitCode.config.code,
        );
      }
      final stem = p.basenameWithoutExtension(entity.path);
      if (!RegExp(r'^[0-9]+_[A-Za-z0-9_]+$').hasMatch(stem) ||
          stem.length > 255) {
        throw MigrationCliException(
          'Invalid migration filename: ${p.basename(entity.path)}. Expected timestamp_name.dart.',
          ExitCode.data.code,
        );
      }
      files.add(entity.absolute);
    }
    files.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    final dart = cli_util.dartExecutable;
    if (dart == null) {
      throw MigrationCliException(
        'Dart SDK not found. Install Dart or set DART_SDK.',
        ExitCode.config.code,
      );
    }
    final cache = Directory(p.join(project.path, '.dart_tool', 'laconic'));
    await cache.create(recursive: true);
    final temporary = await cache.createTemp('run_');
    try {
      final imports = StringBuffer();
      final migrations = StringBuffer();
      final sourceFiles = StringBuffer();
      for (var i = 0; i < files.length; i++) {
        imports.writeln(
          'import ${DartSource.stringLiteral(files[i].uri.toString())} as m$i;',
        );
        sourceFiles.writeln(
          '${DartSource.stringLiteral(p.basenameWithoutExtension(files[i].path))}: ${DartSource.stringLiteral(files[i].path)},',
        );
        migrations.writeln(
          '      checked(${DartSource.stringLiteral(p.basenameWithoutExtension(files[i].path))}, m$i.DatabaseMigration()),',
        );
      }
      final entrypoint = File(p.join(temporary.path, 'main.dart'));
      await entrypoint.writeAsString('''import 'dart:async';
import 'dart:io';
import 'package:laconic/laconic.dart';
import ${DartSource.stringLiteral(config.absolute.uri.toString())} as configuration;
$imports
Future<void> main(List<String> arguments) async {
  Migration checked(String name, Migration migration) {
    if (migration.name != name) {
      throw FormatException('Migration name must match its filename: ' + name);
    }
    return migration;
  }
  final Function factory = configuration.DatabaseConfiguration.createDatabase;
  exitCode = await MigrationCli.runCommand(
    arguments,
    createDatabase: configuration.DatabaseConfiguration.createDatabase,
    resolveConnection: (name) {
      if (factory is FutureOr<Laconic> Function(String)) return factory(name);
      throw LaconicException('Named connections require createDatabase([String? name]) in the configuration.');
    },
    schemaPath: ${DartSource.stringLiteral(p.join(project.path, 'database', 'schema', '${database ?? 'default'}-schema.sql'))},
    migrationFiles: <String, String>{
$sourceFiles    },
    migrations: () => <Migration>[
$migrations    ],
    table: ${DartSource.stringLiteral(table)},
  );
}
''');
      final process = await Process.start(dart, [
        'run',
        '--verbosity=error',
        entrypoint.path,
        ...arguments,
      ], workingDirectory: project.path);
      final signals = <StreamSubscription<ProcessSignal>>[
        ProcessSignal.sigint.watch().listen((signal) => process.kill(signal)),
        if (!Platform.isWindows)
          ProcessSignal.sigterm.watch().listen(
            (signal) => process.kill(signal),
          ),
      ];
      try {
        await process.stdin.close();
        await Future.wait([
          process.stdout.transform(utf8.decoder).forEach(output.write),
          process.stderr.transform(utf8.decoder).forEach(errorOutput.write),
        ]);
        final code = await process.exitCode;
        return code < 0 ? 128 - code : code;
      } finally {
        for (final subscription in signals) {
          await subscription.cancel();
        }
      }
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}
