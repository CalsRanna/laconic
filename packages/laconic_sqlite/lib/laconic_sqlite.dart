/// SQLite driver for Laconic query builder.
///
/// This package provides SQLite support for the Laconic query builder.
///
/// ## Usage
///
/// ```dart
/// import 'package:laconic/laconic.dart';
/// import 'package:laconic_sqlite/laconic_sqlite.dart';
///
/// void main() async {
///   final db = Laconic(SqliteDriver(SqliteConfig('app.db')));
///
///   final users = await db.table('users').get();
///
///   await db.close();
/// }
/// ```
library laconic_sqlite;

export 'src/sqlite_config.dart';
export 'src/sqlite_driver.dart';
export 'src/sqlite_grammar.dart';
