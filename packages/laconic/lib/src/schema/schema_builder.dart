import '../grammar/compiled_query.dart';
import '../laconic.dart';
import 'blueprint.dart';
import 'schema_command.dart';
import 'schema_metadata.dart';
import '../exception.dart';

/// Builds and executes table structure operations through the database grammar.
///
/// Definitions are compiled completely before any statement is executed. A
/// native multi-statement operation is not automatically atomic; use an explicit
/// transaction only on databases that support the statements involved. SQLite
/// table rebuilds use a driver-managed transaction or savepoint.
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
    final grammar = _database.grammar;
    final rebuild = grammar.requiresTableRebuild(blueprint);
    Future<void> execute() async {
      final changes = blueprint.commands.whereType<ColumnDefinition>().where(
        (c) => c.isChange,
      );
      for (final column in changes) {
        grammar.validateChangedColumn(column);
      }
      final columns =
          rebuild || changes.isNotEmpty
              ? await getColumns(table)
              : <SchemaColumn>[];
      final objects =
          rebuild
              ? await _rows(grammar.compileSchemaObjects(table))
              : <Map<String, Object?>>[];
      await _execute(
        grammar.compileAlterTable(
          blueprint,
          columns: columns,
          objects: objects,
        ),
      );
    }

    if (rebuild) {
      await _database.schemaTransaction(execute);
    } else {
      await execute();
    }
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

  /// Returns table metadata for the selected database schema.
  Future<List<SchemaTable>> getTables({String? schema}) async =>
      (await _rows(
        _database.grammar.compileTables(schema: schema),
      )).map(_tableMetadata).toList();

  /// Returns view names and definitions for the selected database schema.
  Future<List<SchemaTable>> getViews({String? schema}) async =>
      (await _rows(
        _database.grammar.compileViews(schema: schema),
      )).map(_tableMetadata).toList();

  SchemaTable _tableMetadata(Map<String, Object?> row) => SchemaTable(
    row['name'] as String,
    row['schema'] as String,
    definition: row['definition'] as String?,
  );

  /// Returns ordered column types, nullability, SQL defaults, and generated flags.
  Future<List<SchemaColumn>> getColumns(String table) async =>
      (await _rows(_database.grammar.compileColumns(table)))
          .map(_database.grammar.normalizeColumnMetadata)
          .map(
            (row) => SchemaColumn(
              name: row['name'] as String,
              typeName: row['type_name'] as String,
              type: row['type'] as String,
              nullable: _boolean(row['nullable']),
              defaultValue: row['default_value']?.toString(),
              autoIncrement: _boolean(row['auto_increment']),
              collation: row['collation'] as String?,
              generation: row['generation'] as String?,
              generated: _boolean(row['generated']),
              defaultConstraint: row['default_constraint'] as String?,
              primaryPosition: _integer(row['primary_position']),
            ),
          )
          .toList();

  /// Returns the native column type, optionally including length and precision.
  Future<String> getColumnType(
    String table,
    String column, {
    bool fullDefinition = false,
  }) async {
    final matches = (await getColumns(table)).where((c) => c.name == column);
    if (matches.isEmpty) {
      throw LaconicException('Column does not exist: $column');
    }
    return fullDefinition ? matches.single.type : matches.single.typeName;
  }

  /// Returns whether all requested columns exist with exactly the given names.
  Future<bool> hasColumns(String table, List<String> columns) async {
    final names = await getColumnListing(table);
    return columns.every(names.contains);
  }

  /// Returns indexes with key columns in index order.
  ///
  /// Included, non-key columns are excluded. An expression key is represented
  /// by a null column entry and the database definition when available.
  Future<List<SchemaIndex>> getIndexes(String table) async {
    final groups = _groupRows(
      await _rows(_database.grammar.compileIndexes(table)),
    );
    return groups.values.map((rows) {
      final row = rows.first;
      return SchemaIndex(
        name: row['name'] as String,
        columns: rows.map((r) => r['column_name'] as String?).toList(),
        unique: _boolean(row['is_unique']),
        primary: _boolean(row['is_primary']),
        type: row['type'] as String,
        definition: row['definition'] as String?,
      );
    }).toList();
  }

  /// Returns whether an index matches a name or an ordered list of key columns.
  ///
  /// [type] may be `primary`, `unique`, or the database's index method.
  Future<bool> hasIndex(String table, Object index, {String? type}) async {
    if (index is! String && index is! List<String>) {
      throw LaconicException(
        'Expected an index name or a list of column names',
      );
    }
    return (await getIndexes(table)).any((candidate) {
      final match =
          index is String
              ? candidate.name == index
              : index is List<String> &&
                  index.length == candidate.columns.length &&
                  List.generate(
                    index.length,
                    (i) => index[i] == candidate.columns[i],
                  ).every((v) => v);
      return match &&
          (type == null ||
              type == 'primary' && candidate.primary ||
              type == 'unique' && candidate.unique ||
              type == candidate.type);
    });
  }

  /// Returns foreign keys with ordered local and referenced column pairs.
  Future<List<SchemaForeignKey>> getForeignKeys(String table) async {
    final groups = _groupRows(
      await _rows(_database.grammar.compileForeignKeys(table)),
    );
    return groups.values.map((rows) {
      final row = rows.first;
      return SchemaForeignKey(
        name: row['name'] as String?,
        columns: rows.map((r) => r['column_name'] as String).toList(),
        foreignSchema: row['foreign_schema'] as String?,
        foreignTable: row['foreign_table'] as String,
        foreignColumns:
            rows.map((r) => r['foreign_column'] as String?).toList(),
        onUpdate: (row['on_update'] as String).toLowerCase().replaceAll(
          '_',
          ' ',
        ),
        onDelete: (row['on_delete'] as String).toLowerCase().replaceAll(
          '_',
          ' ',
        ),
      );
    }).toList();
  }

  Map<Object, List<Map<String, Object?>>> _groupRows(
    List<Map<String, Object?>> rows,
  ) {
    final groups = <Object, List<Map<String, Object?>>>{};
    for (final row in rows) {
      groups.putIfAbsent(row['id'] ?? row['name']!, () => []).add(row);
    }
    for (final group in groups.values) {
      group.sort(
        (a, b) => _integer(a['position']).compareTo(_integer(b['position'])),
      );
    }
    return groups;
  }

  static bool _boolean(Object? value) =>
      value == true || value == 1 || value == '1';
  static int _integer(Object? value) => value == null ? 0 : int.parse('$value');

  Future<List<Map<String, Object?>>> _rows(CompiledQuery query) async =>
      (await _database.select(
        query.sql,
        query.bindings,
      )).map((row) => row.toMap()).toList();

  Future<void> _execute(List<CompiledQuery> statements) async {
    for (final statement in statements) {
      await _database.statement(statement.sql, statement.bindings);
    }
  }
}
