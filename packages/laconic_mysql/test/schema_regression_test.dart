import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
import '../../laconic/test/regressions/schema_regressions.dart';

void main() => schemaRegressions(
  () => Laconic(
    MysqlDriver(
      const MysqlConfig(
        host: '127.0.0.1',
        database: 'testdb',
        username: 'root',
        password: 'root',
        useSsl: false,
      ),
    ),
  ),
  namespace: 'testdb',
);
