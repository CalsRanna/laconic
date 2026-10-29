import '../exception.dart';
import '../laconic.dart';
import '../query_builder/query_builder.dart';
import '../result.dart';

import 'migration.dart';

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
  Future<List<String>> migrate({bool step = false}) => _exclusive(() async {
    final history = await _history();
    final completed = history.map((row) => row['migration'] as String).toSet();
    final pending =
        _migrations.where((m) => !completed.contains(m.name)).toList();
    if (pending.isEmpty) return [];
    if (!await database.schema.hasTable(table)) {
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
      await _run(migration, () async {
        await migration.up(database);
        await _historyTable.insert([
          {'migration': migration.name, 'batch': batch},
        ]);
      });
      executed.add(migration.name);
      if (step) batch++;
    }
    return executed;
  });

  /// Rolls back the latest batch in reverse execution order.
  ///
  /// With [steps], rolls back that many latest migrations across batches.
  /// All required definitions are checked before the first rollback executes.
  Future<List<String>> rollback({int? steps}) => _exclusive(() async {
    if (steps != null && steps <= 0) {
      throw LaconicException('Rollback steps must be positive');
    }
    final history = (await _history()).reversed.toList();
    if (history.isEmpty) return [];
    final latestBatch = history
        .map((row) => (row['batch'] as num).toInt())
        .reduce((a, b) => a > b ? a : b);
    final selected =
        steps != null
            ? history.take(steps).toList()
            : history.where((row) => row['batch'] == latestBatch).toList();
    return _rollback(selected);
  });

  /// Rolls back all recorded migrations in reverse execution order.
  Future<List<String>> reset() =>
      _exclusive(() async => _rollback((await _history()).reversed.toList()));

  Future<List<String>> _rollback(List<LaconicResult> selected) async {
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
      await _run(migration, () async {
        await migration.down(database);
        await _historyTable.where('id', row['id']).delete();
      });
      rolledBack.add(migration.name);
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
