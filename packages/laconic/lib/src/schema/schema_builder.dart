import '../grammar/compiled_query.dart';
import '../laconic.dart';
import 'blueprint.dart';

/// Builds and executes table structure operations through the database grammar.
///
/// Definitions are compiled completely before any statement is executed. A
/// multi-statement operation is not automatically atomic; use an explicit
/// transaction only on databases that support the statements involved.
class SchemaBuilder {
  final Laconic _database;

  /// Creates a schema builder using [database]'s connection and query hooks.
  SchemaBuilder(Laconic database) : _database = database;

  /// Creates a table and its indexes and constraints.
  Future<void> create(
    String table,
    void Function(Blueprint table) define,
  ) async {
    final blueprint = Blueprint(table);
    define(blueprint);
    await _execute(_database.grammar.compileCreateTable(blueprint));
  }

  /// Applies column, index, and constraint alterations in declaration order.
  Future<void> table(String table, void Function(Blueprint table) alter) async {
    final blueprint = Blueprint(table);
    alter(blueprint);
    await _execute(_database.grammar.compileAlterTable(blueprint));
  }

  /// Drops a table.
  Future<void> drop(String table) =>
      _execute(_database.grammar.compileDropTable(table));

  /// Drops a table if it exists.
  Future<void> dropIfExists(String table) =>
      _execute(_database.grammar.compileDropTable(table, ifExists: true));

  /// Renames a table within its current database schema.
  ///
  /// [to] is an unqualified table name.
  Future<void> rename(String from, String to) =>
      _execute(_database.grammar.compileRenameTable(from, to));

  /// Returns whether a table exists in the selected database schema.
  Future<bool> hasTable(String table) async {
    final query = _database.grammar.compileTableExists(table);
    return (await _database.select(query.sql, query.bindings)).isNotEmpty;
  }

  /// Returns the column names in their database-defined order.
  Future<List<String>> getColumnListing(String table) async {
    final query = _database.grammar.compileColumnListing(table);
    final rows = await _database.select(query.sql, query.bindings);
    return rows.map((row) => row['name'] as String).toList();
  }

  /// Returns whether [table] contains a column with exactly [column]'s name.
  Future<bool> hasColumn(String table, String column) async =>
      (await getColumnListing(table)).contains(column);

  Future<void> _execute(List<CompiledQuery> statements) async {
    for (final statement in statements) {
      await _database.statement(statement.sql, statement.bindings);
    }
  }
}
