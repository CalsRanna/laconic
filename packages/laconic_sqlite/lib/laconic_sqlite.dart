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
///   final laconic = Laconic(SqliteDriver(SqliteConfig('app.db')));
///
///   final users = await laconic.table('users').get();
///
///   await laconic.close();
/// }
/// ```
library;

export 'src/sqlite_config.dart';
export 'src/sqlite_driver.dart';
export 'src/sqlite_grammar.dart';
