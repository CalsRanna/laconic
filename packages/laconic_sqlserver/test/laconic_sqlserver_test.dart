import 'package:test/test.dart';
import '../../laconic/test/regressions/driver_regressions.dart';
import 'test_helper.dart';

void main() {
  setUpAll(SqlserverTestDatabase.prepareDatabase);
  DriverRegressions.register(
    createDatabase: SqlserverTestDatabase.createDatabase,
    createTable: '''create table laconic_driver_contract (
      id int identity(1, 1) primary key,
      name nvarchar(100) unique,
      score float
    )''',
    sessionQuery: 'select @@spid',
    driverName: 'sqlserver',
  );
}
