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
    for (final name in ['migrate', 'rollback', 'status']) {
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
  final bool json;

  MigrationCommandRequest(
    this.name, {
    this.step = false,
    this.steps,
    this.json = false,
  });

  List<String> get arguments => [
    name,
    if (step) '--step',
    if (steps != null) '--step=$steps',
    if (json) '--json',
  ];
}

class DatabaseMigrationCommand extends Command<int> {
  @override
  final String name;
  final StringSink output;
  final ExecuteMigrationCommand execute;

  DatabaseMigrationCommand(this.name, this.output, this.execute) {
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
      MigrationCommandRequest(
        name,
        step: name == 'migrate' && argResults!.flag('step'),
        steps: steps,
        json: name == 'status' && argResults!.flag('json'),
      ),
      this,
    );
  }
}
