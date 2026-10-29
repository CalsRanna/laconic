import 'dart:io';
import 'package:laconic/laconic.dart';
import 'package:laconic_mariadb/laconic_mariadb.dart';

Laconic createDatabase({int maxConnections = 10}) => Laconic(
  MariadbDriver(
    MariadbConfig(
      host: Platform.environment['MARIADB_HOST'] ?? '127.0.0.1',
      port: int.parse(Platform.environment['MARIADB_PORT'] ?? '3307'),
      database: Platform.environment['MARIADB_DATABASE'] ?? 'testdb',
      username: Platform.environment['MARIADB_USER'] ?? 'root',
      password: Platform.environment['MARIADB_PASSWORD'] ?? 'root',
      useSsl: false,
      maxConnections: maxConnections,
    ),
  ),
);
