import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';
import '../../laconic/test/regressions/schema_state_regressions.dart';
import '../../laconic/test/regressions/migration_deployment_regressions.dart';

void main() {
  Laconic connect(String database) => Laconic(
    PostgresqlDriver(
      PostgresqlConfig(
        database: database,
        host: '127.0.0.1',
        port: 5433,
        username: 'postgres',
        password: 'postgres',
        useSsl: false,
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
  }, runner: const DockerSchemaProcessRunner('laconic-postgres', 5432));
}
