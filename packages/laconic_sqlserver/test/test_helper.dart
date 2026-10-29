import 'dart:io';
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlserver/laconic_sqlserver.dart';

abstract final class SqlserverTestDatabase {
  static SqlserverConfig testConfig({
    String? database,
    int maxConnections = 10,
  }) => SqlserverConfig(
    host: Platform.environment['SQLSERVER_HOST'] ?? '127.0.0.1',
    port: int.parse(Platform.environment['SQLSERVER_PORT'] ?? '1433'),
    database:
        database ?? Platform.environment['SQLSERVER_DATABASE'] ?? 'testdb',
    username: Platform.environment['SQLSERVER_USER'] ?? 'sa',
    password: Platform.environment['SQLSERVER_PASSWORD'] ?? 'Laconic_test_123!',
    useSsl: Platform.environment['SQLSERVER_SSL'] == 'true',
    allowBadCertificates:
        Platform.environment['SQLSERVER_TRUST_CERTIFICATE'] == 'true',
    maxConnections: maxConnections,
  );

  static Laconic createDatabase({int maxConnections = 10}) =>
      Laconic(SqlserverDriver(testConfig(maxConnections: maxConnections)));

  static Future<void> prepareDatabase() async {
    if (Platform.environment.containsKey('SQLSERVER_DATABASE')) return;
    final admin = Laconic(SqlserverDriver(testConfig(database: 'master')));
    try {
      await admin.statement(
        "if db_id('testdb') is null create database testdb",
      );
    } finally {
      await admin.close();
    }
  }
}
