import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:io/io.dart';
import 'package:path/path.dart' as p;

import '../laconic.dart';
import '../exception.dart';
import '../migration/migration_lock.dart';
import '../migration/schema_state.dart';
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
    FutureOr<Laconic> Function(String name)? resolveConnection,
    String? schemaPath,
    SchemaProcessRunner? schemaProcessRunner,
    Map<String, String>? migrationFiles,
  }) async {
    if (environment?.trim().toLowerCase() == 'production' &&
        request.name != 'status' &&
        (request.name != 'schema:dump' || request.prune) &&
        !request.pretend &&
        !request.force) {
      throw MigrationCliException(
        'Refusing ${request.name} in production. Pass --force to authorize database changes.',
        ExitCode.config.code,
      );
    }
    if (request.prune && migrationFiles == null) {
      throw MigrationCliException(
        '--prune requires a migration source file registry.',
        ExitCode.config.code,
      );
    }
    final baseline = request.schemaPath ?? schemaPath;
    if (request.name == 'schema:dump' && baseline == null) {
      throw MigrationCliException(
        'schema:dump requires --schema-path or a configured schemaPath.',
        ExitCode.usage.code,
      );
    }
    final registered = List<Migration>.of(migrations());
    final owned = <Laconic>{};
    final connections = <String, Future<Laconic>>{};
    Future<Laconic> resolve(String name) => connections.putIfAbsent(
      name,
      () async {
        if (resolveConnection == null) {
          throw LaconicException('No resolver for database connection: $name');
        }
        final connection = await resolveConnection(name);
        owned.add(connection);
        return connection;
      },
    );
    try {
      final db =
          request.database == null
              ? await createDatabase()
              : await resolve(request.database!);
      owned.add(db);
      final migrator = Migrator(
        db,
        migrations: registered,
        table: table,
        resolveConnection: resolve,
        schemaPath: baseline,
        schemaProcessRunner: schemaProcessRunner,
      );
      var skippedCount = 0;
      void skipped(String name) {
        skippedCount++;
        output.writeln('Skipped: $name');
      }

      void nothingApplied() => output.writeln(
        skippedCount == 0
            ? 'No pending migrations.'
            : 'No migrations applied; skipped migrations remain pending.',
      );
      void loaded(String path) => output.writeln(
        '${request.pretend ? 'Would load schema' : 'Loaded schema'}: $path',
      );
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
            isolated: request.isolated,
            pretend: request.pretend,
            onQuery: query,
            onApplied: applied,
            onSkipped: skipped,
            onSchemaLoaded: loaded,
          );
          if (names.isEmpty) nothingApplied();
        case 'rollback':
          final names = await migrator.rollback(
            steps: request.steps,
            isolated: request.isolated,
            batch: request.batch,
            pretend: request.pretend,
            onQuery: query,
            onRolledBack: reversed,
          );
          if (names.isEmpty) output.writeln('Nothing to roll back.');
        case 'reset':
          final names = await migrator.reset(
            isolated: request.isolated,
            pretend: request.pretend,
            onQuery: query,
            onRolledBack: reversed,
          );
          if (names.isEmpty) output.writeln('Nothing to roll back.');
        case 'refresh':
          final names = await migrator.refresh(
            steps: request.steps,
            isolated: request.isolated,
            onApplied: applied,
            onSkipped: skipped,
            onSchemaLoaded: loaded,
            onRolledBack: reversed,
          );
          if (names.isEmpty) nothingApplied();
        case 'fresh':
          final names = await migrator.fresh(
            step: request.step,
            isolated: request.isolated,
            onDropped: () => output.writeln('Dropped all tables.'),
            onApplied: applied,
            onSkipped: skipped,
            onSchemaLoaded: loaded,
          );
          if (names.isEmpty) nothingApplied();
        case 'schema:dump':
          await migrator.dumpSchema(
            baseline!,
            onDumped: (names) async {
              output.writeln('Schema dumped: $baseline');
              if (!request.prune) return;
              final files = <File>[];
              for (final name in names) {
                final path = migrationFiles![name];
                if (path == null) continue; // Already-pruned baseline entries.
                if (await FileSystemEntity.type(path, followLinks: false) !=
                        FileSystemEntityType.file ||
                    p.equals(p.absolute(path), p.absolute(baseline))) {
                  throw LaconicException(
                    'Cannot prune migration source: $path',
                  );
                }
                files.add(File(path));
              }
              for (final file in files) {
                await file.delete();
                output.writeln('Pruned: ${p.basename(file.path)}');
              }
            },
          );
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
                    if (state.baseline) 'baseline': true,
                  },
              ]),
            );
          } else {
            if (states.isEmpty) output.writeln('No migrations.');
            for (final state in states) {
              output.writeln(
                '${state.baseline
                    ? 'BASELINE'
                    : state.missing
                    ? 'MISSING'
                    : state.hasRun
                    ? 'APPLIED'
                    : 'PENDING'}\t${state.batch ?? '-'}\t${state.name}',
              );
            }
          }
      }
      return ExitCode.success.code;
    } on MigrationLockException {
      output.writeln(
        'Skipped: another migration operation holds the database lock.',
      );
      return ExitCode.success.code;
    } finally {
      await Future.wait(owned.map((connection) => connection.close()));
    }
  }
}
