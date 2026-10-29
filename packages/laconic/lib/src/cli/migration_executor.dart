import 'dart:async';
import 'dart:convert';

import 'package:io/io.dart';

import '../laconic.dart';
import '../migrations/migration.dart';
import '../migrations/migrator.dart';
import 'command_runner.dart';

Future<int> executeMigrationCommand(
  MigrationCommandRequest request, {
  required FutureOr<Laconic> Function() createDatabase,
  required Iterable<Migration> Function() migrations,
  required String table,
  required StringSink output,
}) async {
  final registered = List<Migration>.of(migrations());
  final db = await createDatabase();
  try {
    final migrator = Migrator(db, migrations: registered, table: table);
    switch (request.name) {
      case 'migrate':
        final applied = await migrator.migrate(step: request.step);
        if (applied.isEmpty) output.writeln('No pending migrations.');
        for (final name in applied) {
          output.writeln('Migrated: $name');
        }
      case 'rollback':
        final reversed = await migrator.rollback(steps: request.steps);
        if (reversed.isEmpty) output.writeln('Nothing to roll back.');
        for (final name in reversed) {
          output.writeln('Rolled back: $name');
        }
      case 'status':
        final states = await migrator.status();
        if (request.json) {
          output.writeln(
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
          if (states.isEmpty) output.writeln('No migrations.');
          for (final state in states) {
            output.writeln(
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
}
