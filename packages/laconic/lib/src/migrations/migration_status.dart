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
