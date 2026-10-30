import '../exception.dart';

/// Optional driver support for a database-wide, nonblocking migration lock.
///
/// The lock must survive individual migration commits and be released on
/// completion or failure. Competing owners throw [MigrationLockException].
abstract interface class MigrationLockDriver {
  /// Runs [action] while exclusively owning the database's migration lock.
  Future<T> withMigrationLock<T>(Future<T> Function() action);
}

/// Another process or connection already owns the migration lock.
class MigrationLockException extends LaconicException {
  /// Creates a lock contention error, distinct from database failures.
  MigrationLockException()
    : super('Another migration operation holds the database lock');
}
