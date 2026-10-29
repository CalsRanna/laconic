import 'test_helper.dart';
import '../../laconic/test/migrator_regressions.dart';

void main() => migratorRegressions(createDatabase, prepare: prepareDatabase);
