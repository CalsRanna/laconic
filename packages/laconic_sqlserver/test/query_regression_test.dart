import 'package:test/test.dart';
import '../../laconic/test/regressions/query_regressions.dart';
import 'test_helper.dart';

void main() {
  setUpAll(SqlserverTestDatabase.prepareDatabase);
  QueryRegressions.register(
    SqlserverTestDatabase.createDatabase,
    supportsInsertOrIgnore: false,
    supportsOrderedWrites: false,
  );
}
