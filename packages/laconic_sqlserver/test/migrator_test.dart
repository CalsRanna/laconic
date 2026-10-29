import 'test_helper.dart';
import '../../laconic/test/regressions/migrator_regressions.dart';

void main() => migratorRegressions(createDatabase, prepare: prepareDatabase);
