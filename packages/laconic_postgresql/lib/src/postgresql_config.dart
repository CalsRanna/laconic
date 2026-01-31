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

  /// Whether to use SSL.
  final bool useSsl;

  /// Connection username.
  final String username;

  /// Creates a new PostgreSQL configuration.
  const PostgresqlConfig({
    required this.database,
    this.host = '127.0.0.1',
    required this.password,
    this.port = 5432,
    this.useSsl = true,
    this.username = 'postgres',
  });
}
