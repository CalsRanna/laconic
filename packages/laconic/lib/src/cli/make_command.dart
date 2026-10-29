import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:io/io.dart';
import 'package:path/path.dart' as p;

import 'migration_generator.dart';

class MakeMigrationCommand extends Command<int> {
  final StringSink output;
  final Directory project;

  MakeMigrationCommand(this.output, this.project) {
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
      final file = await MigrationGenerator.generate(
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
