import 'package:laconic/laconic.dart';
import 'package:laconic_mariadb/laconic_mariadb.dart';
import '../../laconic/test/regressions/schema_state_regressions.dart';
import '../../laconic/test/regressions/migration_deployment_regressions.dart';

void main() {
  Laconic connect(String database) => Laconic(
    MariadbDriver(
      MariadbConfig(
        database: database,
        host: '127.0.0.1',
        port: 3307,
        username: 'root',
        password: 'root',
        useSsl: false,
        maxConnections: 1,
      ),
    ),
  );
  MigrationDeploymentRegressions.registerContention(() => connect('testdb'));
  SchemaStateRegressions.register(() async {
    final name = 'laconic_dump_${DateTime.now().microsecondsSinceEpoch}';
    final admin = connect('testdb');
    final quoted = admin.grammar.quoteSchemaIdentifier(name);
    await admin.statement('create database $quoted');
    final db = connect(name);
    return SchemaTestDatabase(db, () async {
      await db.close();
      try {
        await admin.statement('drop database $quoted');
      } finally {
        await admin.close();
      }
    });
  }, runner: const DockerSchemaProcessRunner('laconic-mariadb', 3306));
}
