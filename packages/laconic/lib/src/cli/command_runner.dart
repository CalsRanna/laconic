import 'package:args/command_runner.dart';
import 'package:io/io.dart';

import 'cli_exception.dart';

typedef ExecuteMigrationCommand =
    Future<int> Function(
      MigrationCommandRequest request,
      DatabaseMigrationCommand command,
    );

class MigrationCommandRunner extends CommandRunner<int> {
  Future<int> runSafely(List<String> args, StringSink error) async {
    try {
      if (args.isEmpty) {
        usageException('Provide a command, or use --help.');
      }
      return await run(args) ?? ExitCode.success.code;
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

  final StringSink output;

  MigrationCommandRunner(this.output, ExecuteMigrationCommand execute)
    : super('laconic', 'Generate and run Laconic database migrations.') {
    for (final name in [
      'migrate',
      'rollback',
      'reset',
      'refresh',
      'fresh',
      'status',
      'schema:dump',
    ]) {
      addCommand(DatabaseMigrationCommand(name, output, execute));
    }
  }

  @override
  void printUsage() => output.writeln(usage);
}

class MigrationCommandRequest {
  final String name;
  final bool step;
  final int? steps;
  final int? batch;
  final bool json;
  final bool pretend;
  final bool force;
  final bool isolated;
  final bool prune;
  final String? database;
  final String? schemaPath;

  MigrationCommandRequest(
    this.name, {
    this.step = false,
    this.steps,
    this.batch,
    this.json = false,
    this.pretend = false,
    this.force = false,
    this.isolated = false,
    this.prune = false,
    this.database,
    this.schemaPath,
  });

  List<String> get arguments => [
    name,
    if (step) '--step',
    if (steps != null) '--step=$steps',
    if (batch != null) '--batch=$batch',
    if (json) '--json',
    if (pretend) '--pretend',
    if (force) '--force',
    if (isolated) '--isolated',
    if (prune) '--prune',
    if (database != null) '--database=$database',
    if (schemaPath != null) '--schema-path=$schemaPath',
  ];
}

class DatabaseMigrationCommand extends Command<int> {
  @override
  final String name;
  final StringSink output;
  final ExecuteMigrationCommand execute;

  DatabaseMigrationCommand(this.name, this.output, this.execute) {
    if (name == 'migrate' || name == 'fresh') {
      argParser.addFlag(
        'step',
        negatable: false,
        help: 'Give each migration its own batch.',
      );
    } else if (name == 'rollback' || name == 'refresh') {
      argParser.addOption(
        'step',
        valueHelp: 'count',
        help:
            name == 'refresh'
                ? 'Roll back this many migrations instead of all, then migrate.'
                : 'Roll back this many migrations instead of the latest batch.',
      );
    } else if (name == 'status') {
      argParser.addFlag(
        'json',
        negatable: false,
        help: 'Output machine-readable migration status.',
      );
    }
    if (name == 'rollback') {
      argParser.addOption(
        'batch',
        valueHelp: 'number',
        help: 'Roll back one specific batch. Cannot be combined with --step.',
      );
    }
    if (const ['migrate', 'rollback', 'reset'].contains(name)) {
      argParser.addFlag(
        'pretend',
        negatable: false,
        help: 'Print migration SQL without executing it or changing history.',
      );
    }
    argParser.addOption('database', help: 'Use a named database connection.');
    argParser.addOption(
      'schema-path',
      help: 'Path to a native SQL schema baseline.',
    );
    if (name == 'schema:dump') {
      argParser.addFlag(
        'prune',
        negatable: false,
        help: 'Delete applied migration source files after saving the dump.',
      );
    }
    if (name != 'status') {
      argParser.addFlag(
        'isolated',
        negatable: false,
        help: 'Skip if another cooperating migration process holds the lock.',
      );
      argParser.addFlag(
        'force',
        negatable: false,
        help: 'Allow this command when APP_ENV is production.',
      );
    }
  }

  @override
  String get description => switch (name) {
    'migrate' => 'Execute pending migrations.',
    'rollback' => 'Roll back the latest batch or a number of migrations.',
    'reset' => 'Roll back all recorded migrations.',
    'refresh' => 'Roll back migrations, then execute pending migrations.',
    'fresh' => 'Drop every table in the history schema, then migrate.',
    'schema:dump' =>
      'Save native schema and migration history to a SQL baseline.',
    _ => 'Show pending, applied, and missing migrations.',
  };

  @override
  List<String> get aliases =>
      name == 'migrate' || name == 'schema:dump' ? [] : ['migrate:$name'];

  @override
  void printUsage() => output.writeln(usage);

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Unexpected positional arguments.');
    }
    int? positiveOption(String option) {
      final value = argResults!.option(option);
      if (value == null) return null;
      final number = int.tryParse(value);
      if (number == null || number <= 0) {
        usageException('--$option must be a positive integer.');
      }
      return number;
    }

    final steps =
        name == 'rollback' || name == 'refresh' ? positiveOption('step') : null;
    final batch = name == 'rollback' ? positiveOption('batch') : null;
    if (steps != null && batch != null) {
      usageException('--step and --batch cannot be combined.');
    }
    final database = argResults!.option('database');
    if (database != null && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(database)) {
      usageException(
        '--database must be a nonempty connection name (letters, digits, _ or -).',
      );
    }
    final schemaPath = argResults!.option('schema-path');
    if (schemaPath != null && schemaPath.trim().isEmpty) {
      usageException('--schema-path cannot be empty.');
    }
    return execute(
      MigrationCommandRequest(
        name,
        step:
            (name == 'migrate' || name == 'fresh') && argResults!.flag('step'),
        steps: steps,
        batch: batch,
        json: name == 'status' && argResults!.flag('json'),
        pretend:
            const ['migrate', 'rollback', 'reset'].contains(name) &&
            argResults!.flag('pretend'),
        force: name != 'status' && argResults!.flag('force'),
        isolated: name != 'status' && argResults!.flag('isolated'),
        prune: name == 'schema:dump' && argResults!.flag('prune'),
        database: database,
        schemaPath: schemaPath,
      ),
      this,
    );
  }
}
