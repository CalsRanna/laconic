import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';
import '../../laconic/test/regressions/query_regressions.dart';

void main() => QueryRegressions.register(
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
  supportsWriteOffset: true,
);
