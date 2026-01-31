/// A Laravel-style SQL query builder for Dart.
///
/// Laconic provides a fluent, chainable API for building and executing
/// database queries with support for MySQL, SQLite, and PostgreSQL.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:laconic/laconic.dart';
/// import 'package:laconic_sqlite/laconic_sqlite.dart';
///
/// void main() async {
///   // Create a database connection
///   final db = Laconic(SqliteDriver(SqliteConfig('app.db')));
///
///   // Query the database
///   final users = await db.table('users')
///       .where('active', true)
///       .orderBy('name')
///       .get();
///
///   // Don't forget to close the connection
///   await db.close();
/// }
/// ```
///
/// ## Available Drivers
///
/// - `laconic_sqlite` - SQLite driver
/// - `laconic_mysql` - MySQL driver
/// - `laconic_postgresql` - PostgreSQL driver
///
/// ## Custom Drivers
///
/// You can create custom drivers by implementing [LaconicDriver]:
///
/// ```dart
/// class MyDriver implements LaconicDriver {
///   @override
///   Grammar get grammar => MyGrammar();
///
///   // Implement other methods...
/// }
/// ```
library laconic;

export 'src/driver.dart';
export 'src/exception.dart';
export 'src/laconic.dart';
export 'src/query.dart';
export 'src/query_builder/grammar/compiled_query.dart';
export 'src/query_builder/grammar/grammar.dart';
export 'src/query_builder/join_clause.dart';
export 'src/query_builder/query_builder.dart';
export 'src/result.dart';
