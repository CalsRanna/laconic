/// PostgreSQL connection configuration.
class PostgresqlConfig {
  /// Database name.
  final String database;

  /// PostgreSQL host address.
  final String host;

  /// Connection password.
  final String password;

  /// Connection port.
  final int port;

  /// Connection username.
  final String username;

  /// Whether to use SSL connection.
  final bool useSsl;

  /// Application name for PostgreSQL connection.
  final String? applicationName;

  const PostgresqlConfig({
    required this.database,
    this.host = '127.0.0.1',
    required this.password,
    this.port = 5432,
    this.username = 'postgres',
    this.useSsl = false,
    this.applicationName,
  });
}
