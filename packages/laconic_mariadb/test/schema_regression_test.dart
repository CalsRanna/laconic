import '../../laconic/test/schema_regressions.dart';
import 'test_helper.dart';

void main() => schemaRegressions(createDatabase, namespace: 'testdb');
