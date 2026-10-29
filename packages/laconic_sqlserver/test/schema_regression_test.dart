import 'package:test/test.dart';
import '../../laconic/test/regressions/schema_regressions.dart';
import 'test_helper.dart';

void main() {
  setUpAll(prepareDatabase);
  schemaRegressions(createDatabase, namespace: 'dbo');
}
