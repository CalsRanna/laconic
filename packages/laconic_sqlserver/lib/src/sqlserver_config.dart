/// Connection settings for SQL Server 2022 or later.
class SqlserverConfig {
  final String host;
  final int port;
  final String database;
  final String username;
  final String password;
  final bool useSsl;
  final bool allowBadCertificates;
  final int maxConnections;
  final Duration connectTimeout;
  final Duration acquireTimeout;

  const SqlserverConfig({
    required this.database,
    required this.password,
    this.host = '127.0.0.1',
    this.port = 1433,
    this.username = 'sa',
    this.useSsl = true,
    this.allowBadCertificates = false,
    this.maxConnections = 10,
    this.connectTimeout = const Duration(seconds: 30),
    this.acquireTimeout = const Duration(seconds: 15),
  }) : assert(maxConnections > 0, 'maxConnections must be greater than zero');
}
