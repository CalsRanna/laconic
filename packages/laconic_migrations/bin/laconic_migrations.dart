import 'dart:io';

import 'package:laconic_migrations/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runMigrationCli(arguments);
}
