/// SQLite configuration.
class SqliteConfig {
  /// Path to the SQLite database file.
  final String path;

  /// Creates a new SQLite configuration.
  ///
  /// [path] is the path to the SQLite database file.
  /// Use ':memory:' for an in-memory database.
  const SqliteConfig(this.path);
}
