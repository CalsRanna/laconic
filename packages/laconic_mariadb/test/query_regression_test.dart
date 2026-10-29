import '../../laconic/test/regressions/query_regressions.dart';
import 'test_helper.dart';

void main() => QueryRegressions.register(MariadbTestDatabase.createDatabase);
