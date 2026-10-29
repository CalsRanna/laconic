import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
import '../../laconic/test/migrator_regressions.dart';

void main() => migratorRegressions(
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
);
