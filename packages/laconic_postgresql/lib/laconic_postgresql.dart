/// PostgreSQL driver for Laconic query builder.
///
/// This package provides PostgreSQL support for the Laconic query builder.
///
/// ## Usage
///
/// ```dart
/// import 'package:laconic/laconic.dart';
/// import 'package:laconic_postgresql/laconic_postgresql.dart';
///
/// void main() async {
///   final db = Laconic(PostgresqlDriver(PostgresqlConfig(
///     database: 'mydb',
///     password: 'secret',
///   )));
///
///   final users = await db.table('users').get();
///
///   await db.close();
/// }
/// ```
library laconic_postgresql;

export 'src/postgresql_config.dart';
export 'src/postgresql_driver.dart';
