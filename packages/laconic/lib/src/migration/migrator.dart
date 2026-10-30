import '../database/result.dart';
import '../database/query.dart';
import '../exception.dart';
import '../laconic.dart';
import '../query/query_builder.dart';

import 'migration.dart';
import 'migration_status.dart';
import 'migration_preview.dart';

/// Runs explicitly registered migrations and records successful operations.
///
/// Run one migrator at a time per database. This class prevents overlapping
/// mutations on the same instance, but does not provide a distributed lock.
/// On non-transactional DDL engines, a failed migration can leave partial
/// changes that must be repaired before retrying.
class Migrator {
  /// The database connection used for both migrations and their history.
  final Laconic database;

  /// The table storing migration names and execution batches.
  final String table;
  final List<Migration> _migrations;
  bool _running = false;

  /// Creates a migrator with a snapshot of the explicitly registered migrations.
  ///
  /// Registration uses ordinary Dart imports and works in compiled programs.
  Migrator(
    this.database, {
    required Iterable<Migration> migrations,
    this.table = 'migrations',
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
    final result = [
      for (final migration in _migrations)
        MigrationStatus(name: migration.name, batch: batches[migration.name]),
      for (final entry in batches.entries)
        if (!known.contains(entry.key))
          MigrationStatus(name: entry.key, batch: entry.value, missing: true),
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
    bool pretend = false,
    void Function(LaconicQuery query)? onQuery,
    void Function(String name)? onApplied,
  }) => _exclusive(
    () => _migrate(
      step: step,
      pretend: pretend,
      onQuery: onQuery,
      onApplied: onApplied,
    ),
  );

  Future<List<String>> _migrate({
    bool step = false,
    bool pretend = false,
    void Function(LaconicQuery query)? onQuery,
    void Function(String name)? onApplied,
  }) async {
    final history = await _history();
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
      await _execute(migration, 'up', () async {
        if (pretend) {
          await migration.up(
            MigrationPreviewDatabase(database, onQuery ?? (_) {}),
          );
        } else {
          await _run(migration, () async {
            await migration.up(database);
            await _historyTable.insert([
              {'migration': migration.name, 'batch': batch},
            ]);
          });
        }
      });
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
    void Function(LaconicQuery query)? onQuery,
    void Function(String name)? onRolledBack,
  }) => _exclusive(
    () async => _rollback(
      await _selectRollback(steps: steps, batch: batch),
      pretend: pretend,
      onQuery: onQuery,
      onRolledBack: onRolledBack,
    ),
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
    void Function(LaconicQuery query)? onQuery,
    void Function(String name)? onRolledBack,
  }) => _exclusive(
    () async => _rollback(
      (await _history()).reversed.toList(),
      pretend: pretend,
      onQuery: onQuery,
      onRolledBack: onRolledBack,
    ),
  );

  /// Rolls back all migrations, or the latest [steps], then runs pending ones.
  ///
  /// A rollback failure prevents the migrate phase. Successfully reverted
  /// migrations remain reverted if a later rollback or migration fails.
  Future<List<String>> refresh({
    int? steps,
    void Function(String name)? onApplied,
    void Function(String name)? onRolledBack,
  }) => _exclusive(() async {
    final selected =
        steps == null
            ? (await _history()).reversed.toList()
            : await _selectRollback(steps: steps);
    await _rollback(selected, onRolledBack: onRolledBack);
    return _migrate(onApplied: onApplied);
  });

  /// Drops all tables in the history table's schema, then runs migrations.
  ///
  /// Includes tables not managed by migrations. Unqualified history tables use
  /// the grammar's default schema. Views and external dependencies remain and
  /// may prevent dropping tables. The wipe and migrations are separate operations.
  Future<List<String>> fresh({
    bool step = false,
    void Function()? onDropped,
    void Function(String name)? onApplied,
  }) => _exclusive(() async {
    final parts = database.grammar.schemaTableParts(table);
    await database.schema.dropAllTables(
      schema: parts.length == 2 ? parts.first : null,
    );
    onDropped?.call();
    return _migrate(step: step, onApplied: onApplied);
  });

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
      final migration = definitions[row['migration']]!;
      await _execute(migration, 'down', () async {
        if (pretend) {
          await migration.down(
            MigrationPreviewDatabase(database, onQuery ?? (_) {}),
          );
        } else {
          await _run(migration, () async {
            await migration.down(database);
            await _historyTable.where('id', row['id']).delete();
          });
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

  Future<void> _run(Migration migration, Future<void> Function() action) async {
    if (migration.withinTransaction &&
        database.grammar.supportsSchemaTransactions) {
      await database.transaction(action);
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

  Future<List<String>> _exclusive(
    Future<List<String>> Function() action,
  ) async {
    if (_running) {
      throw LaconicException('A migration operation is already running');
    }
    _running = true;
    try {
      return await action();
    } finally {
      _running = false;
    }
  }
}
