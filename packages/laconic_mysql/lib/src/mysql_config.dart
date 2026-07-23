import 'dart:io';

/// MySQL connection configuration.
class MysqlConfig {
  /// Whether to negotiate TLS with the server.
  final bool useSsl;

  /// Whether an invalid TLS certificate may be accepted.
  ///
  /// This is intended only for explicitly opted-in development environments.
  /// Production callers should leave this disabled and configure
  /// [securityContext] with the required CA certificates.
  final bool allowBadCertificates;

  /// Optional TLS trust configuration.
  final SecurityContext? securityContext;

  /// Maximum time allowed for opening and authenticating a connection.
  final Duration connectTimeout;

  /// Maximum time allowed for a database command to complete.
  final Duration commandTimeout;

  /// Database name.
  final String database;

  /// MySQL host address.
  final String host;

  /// Maximum number of connections in the pool.
  ///
  /// Defaults to 10 for compatibility with previous releases.
  final int maxConnections;

  /// Connection password.
  final String password;

  /// Connection port.
  final int port;

  /// Connection username.
  final String username;

  /// Creates a new MySQL configuration.
  const MysqlConfig({
    required this.database,
    this.allowBadCertificates = false,
    this.commandTimeout = const Duration(seconds: 10),
    this.connectTimeout = const Duration(seconds: 10),
    this.host = '127.0.0.1',
    this.maxConnections = 10,
    required this.password,
    this.port = 3306,
    this.securityContext,
    this.useSsl = true,
    this.username = 'root',
  }) : assert(maxConnections > 0, 'maxConnections must be greater than zero');
}
