import 'test_helper.dart';
import '../../laconic/test/regressions/migrator_regressions.dart';

void main() => MigratorRegressions.register(
  SqlserverTestDatabase.createDatabase,
  prepare: SqlserverTestDatabase.prepareDatabase,
  namespaceType: 'schema',
);
