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
///   final laconic = Laconic(PostgresqlDriver(PostgresqlConfig(
///     database: 'database',
///     password: 'password',
///   )));
///
///   final users = await laconic.table('users').get();
///
///   await laconic.close();
/// }
/// ```
library;

export 'src/postgresql_config.dart';
export 'src/postgresql_driver.dart';
export 'src/postgresql_grammar.dart';
