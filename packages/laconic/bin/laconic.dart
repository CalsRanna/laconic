import 'dart:io';

import 'package:laconic/cli.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runMigrationCli(arguments);
}
