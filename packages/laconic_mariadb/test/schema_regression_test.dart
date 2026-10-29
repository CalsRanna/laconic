import '../../laconic/test/regressions/schema_regressions.dart';
import 'test_helper.dart';

void main() => SchemaRegressions.register(
  MariadbTestDatabase.createDatabase,
  namespace: 'testdb',
);
