import '../../laconic/test/regressions/driver_regressions.dart';
import 'test_helper.dart';

void main() => DriverRegressions.register(
  createDatabase: MariadbTestDatabase.createDatabase,
  createTable: '''create table laconic_driver_contract (
    id int primary key auto_increment,
    name varchar(100) unique,
    score double
  )''',
  sessionQuery: 'select connection_id()',
  driverName: 'mariadb',
);
