import '../laconic.dart';

/// A versioned database change with an explicitly authored reverse operation.
abstract class Migration {
  /// Creates a migration.
  const Migration();

  /// The unique, stable migration name, ordered lexicographically.
  ///
  /// Use timestamp-prefixed names such as `202610290001_create_users`.
  /// Names may contain ASCII letters, numbers, and underscores, up to 255
  /// characters. Do not rename or edit migrations that have already run.
  /// Names differing only by letter case are considered duplicates.
  String get name;

  /// Whether to wrap this migration and its history update in one transaction.
  ///
  /// This applies only when the grammar supports transactional schema changes.
  /// Override with `false` for statements that cannot run in a transaction.
  bool get withinTransaction => true;

  /// Applies the change through [database].
  Future<void> up(Laconic database);

  /// Reverses the change through [database].
  ///
  /// Recreating a dropped table does not restore its previous data.
  Future<void> down(Laconic database);
}

/// The recorded or pending state of a migration.
class MigrationStatus {
  /// The stable migration name.
  final String name;

  /// The recorded execution batch, or `null` when pending.
  final int? batch;

  /// Whether an executed migration is absent from the supplied registry.
  final bool missing;

  /// Whether this migration has an execution record.
  bool get hasRun => batch != null;

  /// Creates a migration status.
  const MigrationStatus({required this.name, this.batch, this.missing = false});
}
