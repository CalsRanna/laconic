import 'dart:io';

import 'package:laconic/laconic.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runMigrationCli(arguments);
}
