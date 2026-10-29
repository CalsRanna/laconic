import 'package:laconic_mysql/laconic_mysql.dart';

/// Connection settings for MariaDB 10.11 or later.
class MariadbConfig extends MysqlConfig {
  const MariadbConfig({
    required super.database,
    required super.password,
    super.host,
    super.port,
    super.username,
    super.maxConnections,
    super.useSsl,
    super.allowBadCertificates,
    super.securityContext,
    super.connectTimeout,
    super.commandTimeout,
  });
}
