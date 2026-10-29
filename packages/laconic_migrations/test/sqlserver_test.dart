import '../../laconic_sqlserver/test/test_helper.dart';
import 'migrator_regressions.dart';

void main() => migratorRegressions(createDatabase, prepare: prepareDatabase);
