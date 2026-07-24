/// MySQL driver for Laconic query builder.
///
/// This package provides MySQL support for the Laconic query builder.
///
/// ## Usage
///
/// ```dart
/// import 'package:laconic/laconic.dart';
/// import 'package:laconic_mysql/laconic_mysql.dart';
///
/// void main() async {
///   final laconic = Laconic(MysqlDriver(MysqlConfig(
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

export 'src/mysql_config.dart';
export 'src/mysql_driver.dart';
export 'src/mysql_grammar.dart';
