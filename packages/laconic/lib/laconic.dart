/// A Laravel-style SQL query builder for Dart.
///
/// Laconic provides a fluent, chainable API for building and executing
/// database queries with support for MySQL, SQLite, and PostgreSQL.
/// Schema changes and versioned migrations use [SchemaBuilder] and [Migrator].
///
/// ## Quick Start
///
/// ```dart
/// import 'package:laconic/laconic.dart';
/// import 'package:laconic_sqlite/laconic_sqlite.dart';
///
/// void main() async {
///   // Create a database connection
///   final laconic = Laconic(SqliteDriver(SqliteConfig('app.db')));
///
///   // Query the database
///   final users = await laconic.table('users')
///       .where('active', true)
///       .orderBy('name')
///       .get();
///
///   // Don't forget to close the connection
///   await laconic.close();
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
/// You can create custom drivers by implementing [DatabaseDriver]:
///
/// ```dart
/// class MyDriver implements DatabaseDriver {
///   @override
///   SqlGrammar get grammar => MySqlGrammar();
///
///   // Implement other methods...
/// }
/// ```
library;

export 'src/laconic.dart';
export 'src/exception.dart';

export 'src/database/database_driver.dart';
export 'src/database/query.dart';
export 'src/database/result.dart';

export 'src/query/join_clause.dart';
export 'src/query/pagination.dart';
export 'src/query/query_builder.dart';

export 'src/grammar/compiled_query.dart';
export 'src/grammar/expression.dart';
export 'src/grammar/grammar.dart';

export 'src/schema/blueprint.dart';
export 'src/schema/schema_builder.dart';
export 'src/schema/schema_command.dart';

export 'src/migration/migration.dart';
export 'src/migration/migration_status.dart';
export 'src/migration/migrator.dart';

export 'src/cli/migration_cli.dart';
