import 'dart:async';
import 'dart:io';

import '../database/result.dart';
import '../database/query.dart';
import '../exception.dart';
import '../laconic.dart';
import '../query/query_builder.dart';

import 'migration.dart';
import 'migration_status.dart';
import 'migration_preview.dart';
import 'migration_schema_state.dart';
import 'schema_state.dart';

/// Runs explicitly registered migrations and records successful operations.
///
/// Use `isolated: true` to serialize cooperating processes through the driver's
/// database-wide migration lock. The instance also rejects overlapping mutations.
/// On non-transactional DDL engines, a failed migration can leave partial
/// changes that must be repaired before retrying.
class Migrator {
  /// The default migration connection and the owner of migration history.
  final Laconic database;

  /// The table storing migration names and execution batches.
  final String table;

  /// Resolves named migration connections. Callers retain ownership of them.
  final FutureOr<Laconic> Function(String name)? resolveConnection;

  /// Optional native baseline loaded before migrations on an empty history.
  final String? schemaPath;

  /// Optional native-client runner, for example for containerized clients.
  final SchemaProcessRunner? schemaProcessRunner;
  final Map<String, Future<Laconic>> _connections = {};
  final List<Migration> _migrations;
  bool _running = false;

  /// Creates a migrator with a snapshot of the explicitly registered migrations.
  ///
  /// Registration uses ordinary Dart imports and works in compiled programs.
  Migrator(
    this.database, {
    required Iterable<Migration> migrations,
    this.table = 'migrations',
    this.resolveConnection,
    this.schemaPath,
    this.schemaProcessRunner,
  }) : _migrations = List.of(migrations) {
    database.grammar.quoteSchemaIdentifier(table, qualified: true);
    final names = <String>{};
    for (final migration in _migrations) {
      if (!RegExp(r'^[A-Za-z0-9_]{1,255}$').hasMatch(migration.name)) {
        throw LaconicException('Invalid migration name: ${migration.name}');
      }
      if (!names.add(migration.name.toLowerCase())) {
        throw LaconicException('Duplicate migration name: ${migration.name}');
      }
      if (migration.connection != null &&
          migration.connection!.trim().isEmpty) {
        throw LaconicException('Migration connection names cannot be empty');
      }
    }
    _migrations.sort((a, b) => a.name.compareTo(b.name));
  }

  QueryBuilder get _historyTable => database.table(
    database.grammar.quoteSchemaIdentifier(table, qualified: true),
  );

  /// Lists pending and applied migrations without creating the history table.
  Future<List<MigrationStatus>> status() async {
    final history = await _history();
    final batches = {
      for (final row in history)
        row['migration'] as String: (row['batch'] as num).toInt(),
    };
    final known = _migrations.map((m) => m.name).toSet();
    final path = schemaPath;
    final baselineNames =
        path != null && await File(path).exists()
            ? (await MigrationSchemaState(
              database,
              table,
              schemaProcessRunner,
            ).read(path)).history.map((r) => r['migration']).toSet()
            : <Object?>{};
    final result = [
      for (final migration in _migrations)
        MigrationStatus(name: migration.name, batch: batches[migration.name]),
      for (final entry in batches.entries)
        if (!known.contains(entry.key))
          MigrationStatus(
            name: entry.key,
            batch: entry.value,
            missing: !baselineNames.contains(entry.key),
            baseline: baselineNames.contains(entry.key),
          ),
    ];
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// Runs pending migrations in name order and returns the executed names.
  ///
  /// One call normally forms one batch. With [step], each migration forms its
  /// own batch. Each completed migration is recorded before the next begins.
  /// With [pretend], captures migration SQL through [onQuery] without executing
  /// it or updating history. Schema inspection still reads the current database;
  /// ordinary queries return empty rows or zero. Earlier previewed DDL is not
  /// visible to later inspection. Application side effects are not sandboxed.
  Future<List<String>> migrate({
    bool step = false,
    bool isolated = false,
    bool pretend = false,
    void Function(LaconicQuery query)? onQuery,
    void Function(String name)? onApplied,
    void Function(String name)? onSkipped,
    void Function(String path)? onSchemaLoaded,
  }) => _exclusive(
    () => _migrate(
      step: step,
      pretend: pretend,
      onQuery: onQuery,
      onApplied: onApplied,
      onSkipped: onSkipped,
      onSchemaLoaded: onSchemaLoaded,
    ),
    isolated: isolated,
  );

  Future<List<String>> _migrate({
    bool step = false,
    bool pretend = false,
    void Function(LaconicQuery query)? onQuery,
    void Function(String name)? onApplied,
    void Function(String name)? onSkipped,
    void Function(String path)? onSchemaLoaded,
  }) async {
    var history = await _history();
    final path = schemaPath;
    if (history.isEmpty && path != null && await File(path).exists()) {
      final state = MigrationSchemaState(database, table, schemaProcessRunner);
      final baseline = await state.read(path);
      if (pretend) {
        onQuery?.call(LaconicQuery(sql: baseline.sql, bindings: []));
        history = baseline.history;
      } else {
        await state.load(path);
        history = await _history();
        if (history.length != baseline.history.length ||
            List.generate(
              history.length,
              (i) =>
                  history[i]['migration'] != baseline.history[i]['migration'] ||
                  history[i]['batch'] != baseline.history[i]['batch'],
            ).any((v) => v)) {
          throw LaconicException(
            'Loaded schema history does not match the baseline manifest',
          );
        }
      }
      onSchemaLoaded?.call(path);
    }
    final completed = history.map((row) => row['migration'] as String).toSet();
    final pending =
        _migrations.where((m) => !completed.contains(m.name)).toList();
    if (pending.isEmpty) return [];
    if (!pretend && !await database.schema.hasTable(table)) {
      await database.schema.create(table, (blueprint) {
        blueprint.id();
        blueprint.string('migration');
        blueprint.integer('batch');
        blueprint.unique(['migration']);
      });
    }
    var batch = 1;
    for (final row in history) {
      final next = (row['batch'] as num).toInt() + 1;
      if (next > batch) batch = next;
    }
    final executed = <String>[];
    for (final migration in pending) {
      var skipped = false;
      await _execute(migration, 'up', () async {
        final target = await _target(migration);
        if (!pretend && !await migration.shouldRun(target)) {
          skipped = true;
          return;
        }
        if (pretend) {
          await migration.up(
            MigrationPreviewDatabase(target, onQuery ?? (_) {}),
          );
        } else {
          Future<void> record() async {
            await _historyTable.insert([
              {'migration': migration.name, 'batch': batch},
            ]);
          }

          await _run(migration, target, () async {
            await migration.up(target);
            if (identical(target, database)) await record();
          });
          if (!identical(target, database)) await record();
        }
      });
      if (skipped) {
        onSkipped?.call(migration.name);
        continue;
      }
      executed.add(migration.name);
      onApplied?.call(migration.name);
      if (step) batch++;
    }
    return executed;
  }

  /// Rolls back the latest batch in reverse execution order.
  ///
  /// With [steps], rolls back that many latest migrations across batches.
  /// All required definitions are checked before the first rollback executes.
  /// [batch] selects one batch and cannot be combined with [steps]. [pretend]
  /// captures SQL with the same limitations as [migrate]. [onRolledBack] runs
  /// after each successful rollback (or preview), including before later failures.
  Future<List<String>> rollback({
    int? steps,
    int? batch,
    bool pretend = false,
    bool isolated = false,
    void Function(LaconicQuery query)? onQuery,
    void Function(String name)? onRolledBack,
  }) => _exclusive(
    () async => _rollback(
      await _selectRollback(steps: steps, batch: batch),
      pretend: pretend,
      onQuery: onQuery,
      onRolledBack: onRolledBack,
    ),
    isolated: isolated,
  );

  Future<List<LaconicResult>> _selectRollback({int? steps, int? batch}) async {
    if (steps != null && steps <= 0) {
      throw LaconicException('Rollback steps must be positive');
    }
    if (batch != null && batch <= 0) {
      throw LaconicException('Rollback batch must be positive');
    }
    if (steps != null && batch != null) {
      throw LaconicException('Rollback steps and batch cannot be combined');
    }
    final history = (await _history()).reversed.toList();
    if (history.isEmpty) return [];
    final latestBatch = history
        .map((row) => (row['batch'] as num).toInt())
        .reduce((a, b) => a > b ? a : b);
    final selected =
        steps != null
            ? history.take(steps).toList()
            : history
                .where((row) => row['batch'] == (batch ?? latestBatch))
                .toList();
    return selected;
  }

  /// Rolls back all recorded migrations in reverse execution order.
  Future<List<String>> reset({
    bool pretend = false,
    bool isolated = false,
    void Function(LaconicQuery query)? onQuery,
    void Function(String name)? onRolledBack,
  }) => _exclusive(
    () async => _rollback(
      (await _history()).reversed.toList(),
      pretend: pretend,
      onQuery: onQuery,
      onRolledBack: onRolledBack,
    ),
    isolated: isolated,
  );

  /// Rolls back all migrations, or the latest [steps], then runs pending ones.
  ///
  /// A rollback failure prevents the migrate phase. Successfully reverted
  /// migrations remain reverted if a later rollback or migration fails.
  Future<List<String>> refresh({
    int? steps,
    bool isolated = false,
    void Function(String name)? onApplied,
    void Function(String name)? onRolledBack,
    void Function(String name)? onSkipped,
    void Function(String path)? onSchemaLoaded,
  }) => _exclusive(() async {
    final selected =
        steps == null
            ? (await _history()).reversed.toList()
            : await _selectRollback(steps: steps);
    await _rollback(selected, onRolledBack: onRolledBack);
    return _migrate(
      onApplied: onApplied,
      onSkipped: onSkipped,
      onSchemaLoaded: onSchemaLoaded,
    );
  }, isolated: isolated);

  /// Drops all tables in the history table's schema, then runs migrations.
  ///
  /// Includes tables not managed by migrations. Unqualified history tables use
  /// the grammar's default schema. Views and external dependencies remain and
  /// may prevent dropping tables. The wipe and migrations are separate operations.
  Future<List<String>> fresh({
    bool step = false,
    bool isolated = false,
    void Function()? onDropped,
    void Function(String name)? onApplied,
    void Function(String name)? onSkipped,
    void Function(String path)? onSchemaLoaded,
  }) => _exclusive(() async {
    final parts = database.grammar.schemaTableParts(table);
    await database.schema.dropAllTables(
      schema: parts.length == 2 ? parts.first : null,
    );
    onDropped?.call();
    return _migrate(
      step: step,
      onApplied: onApplied,
      onSkipped: onSkipped,
      onSchemaLoaded: onSchemaLoaded,
    );
  }, isolated: isolated);

  /// Atomically saves native schema and applied migration history to a SQL file.
  ///
  /// Table data is excluded. [onDumped] runs under the same lock after the file
  /// is saved, and receives only applied names eligible for source pruning.
  /// Cross-connection migrations cannot be represented by one schema dump.
  Future<void> dumpSchema(
    String path, {
    bool isolated = true,
    FutureOr<void> Function(List<String> applied)? onDumped,
  }) => _exclusive(() async {
    final history = await _history();
    final definitions = {
      for (final migration in _migrations) migration.name: migration,
    };
    final previous = schemaPath;
    final baselineNames =
        previous != null && await File(previous).exists()
            ? (await MigrationSchemaState(
              database,
              table,
              schemaProcessRunner,
            ).read(previous)).history.map((r) => r['migration']).toSet()
            : <Object?>{};
    for (final row in history) {
      final migration = definitions[row['migration']];
      if (migration == null) {
        if (!baselineNames.contains(row['migration'])) {
          throw LaconicException(
            'Missing migration definition for schema dump: ${row['migration']}',
          );
        }
      } else if (!identical(await _target(migration), database)) {
        throw LaconicException(
          'A schema dump cannot include cross-connection migration ${migration.name}',
        );
      }
    }
    await MigrationSchemaState(
      database,
      table,
      schemaProcessRunner,
    ).dump(path, history);
    await onDumped?.call(
      List.unmodifiable(history.map((r) => r['migration'] as String)),
    );
  }, isolated: isolated);

  Future<List<String>> _rollback(
    List<LaconicResult> selected, {
    bool pretend = false,
    void Function(LaconicQuery query)? onQuery,
    void Function(String name)? onRolledBack,
  }) async {
    final definitions = {
      for (final migration in _migrations) migration.name: migration,
    };
    for (final row in selected) {
      if (!definitions.containsKey(row['migration'])) {
        throw LaconicException(
          'Missing migration definition: ${row['migration']}',
        );
      }
    }
    final rolledBack = <String>[];
    for (final row in selected) {
      await _target(definitions[row['migration']]!);
    }
    for (final row in selected) {
      final migration = definitions[row['migration']]!;
      await _execute(migration, 'down', () async {
        final target = await _target(migration);
        if (pretend) {
          await migration.down(
            MigrationPreviewDatabase(target, onQuery ?? (_) {}),
          );
        } else {
          Future<void> forget() async {
            await _historyTable.where('id', row['id']).delete();
          }

          await _run(migration, target, () async {
            await migration.down(target);
            if (identical(target, database)) await forget();
          });
          if (!identical(target, database)) await forget();
        }
      });
      rolledBack.add(migration.name);
      onRolledBack?.call(migration.name);
    }
    return rolledBack;
  }

  Future<List<LaconicResult>> _history() async {
    if (!await database.schema.hasTable(table)) return [];
    return _historyTable.orderBy('id').get();
  }

  Future<Laconic> _target(Migration migration) async {
    final name = migration.connection;
    if (name == null) return database;
    final resolver = resolveConnection;
    if (resolver == null) {
      throw LaconicException('No resolver for migration connection: $name');
    }
    return _connections.putIfAbsent(
      name,
      () => Future.sync(() => resolver(name)),
    );
  }

  Future<void> _run(
    Migration migration,
    Laconic target,
    Future<void> Function() action,
  ) async {
    if (migration.withinTransaction &&
        target.grammar.supportsSchemaTransactions) {
      await target.transaction(action);
    } else {
      await action();
    }
  }

  Future<void> _execute(
    Migration migration,
    String direction,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      throw LaconicException(
        'Migration ${migration.name} ($direction) failed: $error',
      );
    }
  }

  Future<T> _exclusive<T>(
    Future<T> Function() action, {
    bool isolated = false,
  }) async {
    if (_running) {
      throw LaconicException('A migration operation is already running');
    }
    _running = true;
    try {
      return isolated
          ? await database.withMigrationLock(action)
          : await action();
    } finally {
      _running = false;
    }
  }
}
