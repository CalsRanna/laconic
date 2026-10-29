import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import '../../laconic/test/regressions/migrator_regressions.dart';

void main() => MigratorRegressions.register(
  () => Laconic(SqliteDriver(SqliteConfig(':memory:'))),
);
