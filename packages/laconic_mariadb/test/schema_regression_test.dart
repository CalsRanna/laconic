import '../../laconic/test/regressions/schema_regressions.dart';
import 'test_helper.dart';

void main() => schemaRegressions(createDatabase, namespace: 'testdb');
