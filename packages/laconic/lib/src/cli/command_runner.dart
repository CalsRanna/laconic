import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

import '../laconic.dart';
import '../migrations/migration.dart';
import '../migrations/migrator.dart';
import 'cli_exception.dart';
import 'generator.dart';
import 'project.dart';

/// Runs the project CLI for generating and discovering migration files.
///
/// Paths are relative to [workingDirectory], or the current directory.
/// Execution commands compile a temporary entrypoint using the project's Dart
/// configuration and migration factories. The Dart SDK must be available.
Future<int> runMigrationCli(
  List<String> arguments, {
  Directory? workingDirectory,
  StringSink? output,
  StringSink? errorOutput,
}) async {
  final out = output ?? stdout;
  final err = errorOutput ?? stderr;
  final project = (workingDirectory ?? Directory.current).absolute;
  final runner = _Runner(
    out,
    (request, command) => runProjectMigrations(
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
      help: 'Dart file exporting createDatabase().',
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
  runner.addCommand(_MakeCommand(out, project));
  return _run(runner, arguments, err);
}

/// Runs migration commands with statically imported application dependencies.
///
/// Suitable for generated entrypoints or an application's own compiled CLI.
/// The factories are called only after command validation, never for help.
/// This function owns and closes the connection returned by [createDatabase].
Future<int> runMigrationCommand(
  List<String> arguments, {
  required FutureOr<Laconic> Function() createDatabase,
  required Iterable<Migration> Function() migrations,
  String table = 'migrations',
  StringSink? output,
  StringSink? errorOutput,
}) async {
  final out = output ?? stdout;
  final err = errorOutput ?? stderr;
  final runner = _Runner(out, (request, _) async {
    final registered = List<Migration>.of(migrations());
    final db = await createDatabase();
    try {
      final migrator = Migrator(db, migrations: registered, table: table);
      switch (request.name) {
        case 'migrate':
          final applied = await migrator.migrate(step: request.step);
          if (applied.isEmpty) out.writeln('No pending migrations.');
          for (final name in applied) {
            out.writeln('Migrated: $name');
          }
        case 'rollback':
          final reversed = await migrator.rollback(steps: request.steps);
          if (reversed.isEmpty) out.writeln('Nothing to roll back.');
          for (final name in reversed) {
            out.writeln('Rolled back: $name');
          }
        case 'status':
          final states = await migrator.status();
          if (request.json) {
            out.writeln(
              jsonEncode([
                for (final state in states)
                  {
                    'name': state.name,
                    'status': state.hasRun ? 'applied' : 'pending',
                    'batch': state.batch,
                    'missing': state.missing,
                  },
              ]),
            );
          } else {
            if (states.isEmpty) out.writeln('No migrations.');
            for (final state in states) {
              out.writeln(
                '${state.missing
                    ? 'MISSING'
                    : state.hasRun
                    ? 'APPLIED'
                    : 'PENDING'}\t${state.batch ?? '-'}\t${state.name}',
              );
            }
          }
      }
      return ExitCode.success.code;
    } finally {
      await db.close();
    }
  });
  return _run(runner, arguments, err);
}

Future<int> _run(_Runner runner, List<String> args, StringSink error) async {
  try {
    if (args.isEmpty) {
      runner.usageException('Provide a command, or use --help.');
    }
    return await runner.run(args) ?? ExitCode.success.code;
  } on UsageException catch (e) {
    error
      ..writeln(e.message)
      ..writeln(e.usage);
    return ExitCode.usage.code;
  } on MigrationCliException catch (e) {
    error.writeln(e.message);
    return e.exitCode;
  } on FormatException catch (e) {
    error.writeln(e.message);
    return ExitCode.data.code;
  } catch (e) {
    error.writeln('Migration command failed: $e');
    return ExitCode.software.code;
  }
}

typedef _Execute =
    Future<int> Function(_Request request, _DatabaseCommand command);

class _Runner extends CommandRunner<int> {
  final StringSink output;

  _Runner(this.output, _Execute execute)
    : super('laconic', 'Generate and run Laconic database migrations.') {
    for (final name in ['migrate', 'rollback', 'status']) {
      addCommand(_DatabaseCommand(name, output, execute));
    }
  }

  @override
  void printUsage() => output.writeln(usage);
}

class _Request {
  final String name;
  final bool step;
  final int? steps;
  final bool json;

  _Request(this.name, {this.step = false, this.steps, this.json = false});

  List<String> get arguments => [
    name,
    if (step) '--step',
    if (steps != null) '--step=$steps',
    if (json) '--json',
  ];
}

class _DatabaseCommand extends Command<int> {
  @override
  final String name;
  final StringSink output;
  final _Execute execute;

  _DatabaseCommand(this.name, this.output, this.execute) {
    if (name == 'migrate') {
      argParser.addFlag(
        'step',
        negatable: false,
        help: 'Give each migration its own batch.',
      );
    } else if (name == 'rollback') {
      argParser.addOption(
        'step',
        valueHelp: 'count',
        help: 'Roll back this many migrations instead of the latest batch.',
      );
    } else {
      argParser.addFlag(
        'json',
        negatable: false,
        help: 'Output machine-readable migration status.',
      );
    }
  }

  @override
  String get description => switch (name) {
    'migrate' => 'Execute pending migrations.',
    'rollback' => 'Roll back the latest batch or a number of migrations.',
    _ => 'Show pending, applied, and missing migrations.',
  };

  @override
  List<String> get aliases => name == 'migrate' ? [] : ['migrate:$name'];

  @override
  void printUsage() => output.writeln(usage);

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Unexpected positional arguments.');
    }
    int? steps;
    if (name == 'rollback' && argResults!.option('step') != null) {
      steps = int.tryParse(argResults!.option('step')!);
      if (steps == null || steps <= 0) {
        usageException('--step must be a positive integer.');
      }
    }
    return execute(
      _Request(
        name,
        step: name == 'migrate' && argResults!.flag('step'),
        steps: steps,
        json: name == 'status' && argResults!.flag('json'),
      ),
      this,
    );
  }
}

class _MakeCommand extends Command<int> {
  final StringSink output;
  final Directory project;

  _MakeCommand(this.output, this.project) {
    argParser.addOption(
      'create',
      valueHelp: 'table',
      help: 'Generate create-table and drop-table operations.',
    );
  }

  @override
  String get name => 'make';
  @override
  List<String> get aliases => ['make:migration'];
  @override
  String get description => 'Generate a timestamped migration file.';
  @override
  String get invocation => '${super.invocation} <name>';
  @override
  void printUsage() => output.writeln(usage);

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      usageException('Provide one lower_snake_case migration name.');
    }
    try {
      final file = await generateMigration(
        directory: Directory(
          p.normalize(p.join(project.path, globalResults!.option('path')!)),
        ),
        name: argResults!.rest.single,
        createTable: argResults!.option('create'),
      );
      output.writeln('Created: ${p.relative(file.path, from: project.path)}');
      return ExitCode.success.code;
    } on FormatException catch (e) {
      usageException(e.message);
    }
  }
}
