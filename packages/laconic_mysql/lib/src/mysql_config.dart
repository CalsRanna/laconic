/// MySQL connection configuration.
class MysqlConfig {
  /// Database name.
  final String database;

  /// MySQL host address.
  final String host;

  /// Connection password.
  final String password;

  /// Connection port.
  final int port;

  /// Connection username.
  final String username;

  /// Creates a new MySQL configuration.
  const MysqlConfig({
    required this.database,
    this.host = '127.0.0.1',
    required this.password,
    this.port = 3306,
    this.username = 'root',
  });
}
