import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
import '../../laconic/test/regressions/query_regressions.dart';

void main() => QueryRegressions.register(
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
  supportsLimitedJoinWrites: false,
  upsertUpdateCount: 2,
);
