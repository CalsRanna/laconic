import 'dart:async';

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

  /// The optional named target connection, resolved by the migrator.
  ///
  /// History remains on the migrator's default connection. Cross-connection
  /// changes and history cannot share an atomic transaction.
  String? get connection => null;

  /// Whether to apply this pending migration on its resolved connection.
  ///
  /// False leaves it pending for a later run. Rollbacks always reverse recorded
  /// migrations, regardless of the current condition. Previews skip this check.
  FutureOr<bool> shouldRun(Laconic database) => true;

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
