import 'package:laconic/laconic.dart';
import 'package:test/test.dart';
import 'test_helper.dart';
import '../../laconic/test/regressions/migration_deployment_regressions.dart';

void main() {
  setUpAll(SqlserverTestDatabase.prepareDatabase);
  MigrationDeploymentRegressions.registerContention(
    () => SqlserverTestDatabase.createDatabase(maxConnections: 1),
  );
  test('native schema baselines are explicitly unsupported', () async {
    final db = SqlserverTestDatabase.createDatabase();
    try {
      expect(() => db.schemaState, throwsA(isA<LaconicException>()));
    } finally {
      await db.close();
    }
  });
}
