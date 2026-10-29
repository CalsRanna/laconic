import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import '../../laconic/test/regressions/schema_regressions.dart';

void main() => SchemaRegressions.register(
  () => Laconic(SqliteDriver(SqliteConfig(':memory:'))),
  sqlite: true,
  namespace: 'main',
);
