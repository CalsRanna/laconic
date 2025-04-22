class MysqlConfig {
  final String database;
  final String host;
  final String password;
  final int port;
  final String username;

  const MysqlConfig({
    required this.database,
    this.host = '127.0.0.1',
    required this.password,
    this.port = 3306,
    this.username = 'root',
  });
}
