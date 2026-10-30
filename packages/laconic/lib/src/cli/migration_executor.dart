import 'dart:async';
import 'dart:convert';

import 'package:io/io.dart';

import '../laconic.dart';
import '../database/query.dart';
import '../migration/migration.dart';
import '../migration/migrator.dart';
import 'command_runner.dart';
import 'cli_exception.dart';

abstract final class MigrationExecutor {
  static Future<int> execute(
    MigrationCommandRequest request, {
    required FutureOr<Laconic> Function() createDatabase,
    required Iterable<Migration> Function() migrations,
    required String table,
    required StringSink output,
    String? environment,
  }) async {
    if (environment?.trim().toLowerCase() == 'production' &&
        request.name != 'status' &&
        !request.pretend &&
        !request.force) {
      throw MigrationCliException(
        'Refusing ${request.name} in production. Pass --force to authorize database changes.',
        ExitCode.config.code,
      );
    }
    final registered = List<Migration>.of(migrations());
    final db = await createDatabase();
    try {
      final migrator = Migrator(db, migrations: registered, table: table);
      void applied(String name) => output.writeln(
        '${request.pretend ? 'Would migrate' : 'Migrated'}: $name',
      );
      void reversed(String name) => output.writeln(
        '${request.pretend ? 'Would roll back' : 'Rolled back'}: $name',
      );
      void query(LaconicQuery query) {
        output.writeln('SQL: ${query.sql}');
        if (query.bindings.isNotEmpty) {
          output.writeln(
            'Bindings: ${jsonEncode(query.bindings, toEncodable: (value) => value.toString())}',
          );
        }
      }

      switch (request.name) {
        case 'migrate':
          final names = await migrator.migrate(
            step: request.step,
            pretend: request.pretend,
            onQuery: query,
            onApplied: applied,
          );
          if (names.isEmpty) output.writeln('No pending migrations.');
        case 'rollback':
          final names = await migrator.rollback(
            steps: request.steps,
            batch: request.batch,
            pretend: request.pretend,
            onQuery: query,
            onRolledBack: reversed,
          );
          if (names.isEmpty) output.writeln('Nothing to roll back.');
        case 'reset':
          final names = await migrator.reset(
            pretend: request.pretend,
            onQuery: query,
            onRolledBack: reversed,
          );
          if (names.isEmpty) output.writeln('Nothing to roll back.');
        case 'refresh':
          final names = await migrator.refresh(
            steps: request.steps,
            onApplied: applied,
            onRolledBack: reversed,
          );
          if (names.isEmpty) output.writeln('No pending migrations.');
        case 'fresh':
          final names = await migrator.fresh(
            step: request.step,
            onDropped: () => output.writeln('Dropped all tables.'),
            onApplied: applied,
          );
          if (names.isEmpty) output.writeln('No pending migrations.');
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
}
