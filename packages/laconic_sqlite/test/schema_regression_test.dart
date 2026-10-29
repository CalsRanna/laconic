import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import '../../laconic/test/schema_regressions.dart';

void main() => schemaRegressions(
  () => Laconic(SqliteDriver(SqliteConfig(':memory:'))),
  sqlite: true,
  namespace: 'main',
);
