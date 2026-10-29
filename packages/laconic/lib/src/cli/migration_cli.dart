import 'dart:async';
import 'dart:io';

import '../laconic.dart';
import '../migrations/migration.dart';
import 'command_runner.dart';
import 'make_command.dart';
import 'migration_executor.dart';
import 'migration_project.dart';

/// Command-line entrypoints for generating and running database migrations.
abstract final class MigrationCli {
  /// Runs the project CLI for generating and discovering migration files.
  ///
  /// Paths are relative to [workingDirectory], or the current directory.
  /// Execution commands compile a temporary entrypoint using the project's Dart
  /// configuration and migration classes. The Dart SDK must be available.
  static Future<int> run(
    List<String> arguments, {
    Directory? workingDirectory,
    StringSink? output,
    StringSink? errorOutput,
  }) async {
    final out = output ?? stdout;
    final err = errorOutput ?? stderr;
    final project = (workingDirectory ?? Directory.current).absolute;
    final runner = MigrationCommandRunner(
      out,
      (request, command) => MigrationProject.run(
        project: project,
        configPath: command.globalResults!.option('config')!,
        migrationsPath: command.globalResults!.option('path')!,
        table: command.globalResults!.option('table')!,
        arguments: request.arguments,
        output: out,
        errorOutput: err,
      ),
    );
    runner.argParser
      ..addOption(
        'config',
        defaultsTo: 'database/migrations.dart',
        help: 'Dart file exporting DatabaseConfiguration.createDatabase().',
      )
      ..addOption(
        'path',
        defaultsTo: 'database/migrations',
        help: 'Directory containing timestamp_name.dart migrations.',
      )
      ..addOption(
        'table',
        defaultsTo: 'migrations',
        help: 'Database table storing migration history.',
      );
    runner.addCommand(MakeMigrationCommand(out, project));
    return runner.runSafely(arguments, err);
  }

  /// Runs migration commands with statically imported application dependencies.
  ///
  /// Suitable for generated entrypoints or an application's own compiled CLI.
  /// The factories are called only after command validation, never for help.
  /// Owns and closes the connection returned by [createDatabase].
  static Future<int> runCommand(
    List<String> arguments, {
    required FutureOr<Laconic> Function() createDatabase,
    required Iterable<Migration> Function() migrations,
    String table = 'migrations',
    StringSink? output,
    StringSink? errorOutput,
  }) async {
    final out = output ?? stdout;
    final err = errorOutput ?? stderr;
    final runner = MigrationCommandRunner(out, (request, _) async {
      return MigrationExecutor.execute(
        request,
        createDatabase: createDatabase,
        migrations: migrations,
        table: table,
        output: out,
      );
    });
    return runner.runSafely(arguments, err);
  }
}
