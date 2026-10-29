import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import '../../laconic/test/regressions/query_regressions.dart';

void main() => QueryRegressions.register(
  () => Laconic(SqliteDriver(SqliteConfig(':memory:'))),
);
