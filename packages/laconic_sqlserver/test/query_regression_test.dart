import 'package:test/test.dart';
import '../../laconic/test/regressions/query_regressions.dart';
import 'test_helper.dart';

void main() {
  setUpAll(prepareDatabase);
  queryRegressions(createDatabase, supportsInsertOrIgnore: false);
}
