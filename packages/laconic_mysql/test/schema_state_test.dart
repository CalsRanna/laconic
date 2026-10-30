import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
import '../../laconic/test/regressions/schema_state_regressions.dart';
import '../../laconic/test/regressions/migration_deployment_regressions.dart';

void main() {
  Laconic connect(String database) => Laconic(
    MysqlDriver(
      MysqlConfig(
        database: database,
        host: '127.0.0.1',
        port: 3306,
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
  }, runner: const DockerSchemaProcessRunner('laconic-mysql', 3306));
}
