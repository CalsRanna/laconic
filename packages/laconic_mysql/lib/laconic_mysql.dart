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
///   final db = Laconic(MysqlDriver(MysqlConfig(
///     database: 'mydb',
///     password: 'secret',
///   )));
///
///   final users = await db.table('users').get();
///
///   await db.close();
/// }
/// ```
library laconic_mysql;

export 'src/mysql_config.dart';
export 'src/mysql_driver.dart';
export 'src/mysql_grammar.dart';
