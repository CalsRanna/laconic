import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import '../../laconic/test/migrator_regressions.dart';

void main() =>
    migratorRegressions(() => Laconic(SqliteDriver(SqliteConfig(':memory:'))));
