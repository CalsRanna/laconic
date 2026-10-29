import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';
import 'migrator_regressions.dart';

void main() => migratorRegressions(
  () => Laconic(
    PostgresqlDriver(
      const PostgresqlConfig(
        host: '127.0.0.1',
        port: 5433,
        database: 'testdb',
        username: 'postgres',
        password: 'postgres',
        useSsl: false,
      ),
    ),
  ),
);
