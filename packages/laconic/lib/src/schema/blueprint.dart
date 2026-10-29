import '../exception.dart';
import 'schema_command.dart';

/// Collects ordered commands for creating or altering a table.
class Blueprint {
  /// The unquoted table name, optionally qualified by a schema.
  final String table;
  final List<SchemaCommand> _commands = [];

  /// Creates a definition for [table].
  Blueprint(this.table);

  /// The commands in declaration order.
  List<SchemaCommand> get commands => List.unmodifiable(_commands);

  /// Adds a generated integer primary key.
  ///
  /// Uses a signed BIGINT on server databases and INTEGER on SQLite.
  ColumnDefinition id([String name = 'id']) =>
      _column(name, ColumnType.bigInteger, autoIncrement: true).primary();

  /// Adds an integer column.
  ColumnDefinition integer(String name) => _column(name, ColumnType.integer);

  /// Adds a signed 64-bit integer column.
  ColumnDefinition bigInteger(String name) =>
      _column(name, ColumnType.bigInteger);

  /// Adds a string column with a maximum [length].
  ColumnDefinition string(String name, {int length = 255}) {
    if (length <= 0) throw LaconicException('String length must be positive');
    return _column(name, ColumnType.string, length: length);
  }

  /// Adds a text column.
  ColumnDefinition text(String name) => _column(name, ColumnType.text);

  /// Adds a boolean column.
  ColumnDefinition boolean(String name) => _column(name, ColumnType.boolean);

  /// Adds a decimal column with [precision] digits and [scale] fractional digits.
  ColumnDefinition decimal(String name, {int precision = 10, int scale = 2}) {
    if (precision <= 0 || scale < 0 || scale > precision) {
      throw LaconicException('Invalid decimal precision or scale');
    }
    return _column(
      name,
      ColumnType.decimal,
      precision: precision,
      scale: scale,
    );
  }

  /// Adds a double-precision floating point column.
  ColumnDefinition doublePrecision(String name) =>
      _column(name, ColumnType.doublePrecision);

  /// Adds a date column.
  ColumnDefinition date(String name) => _column(name, ColumnType.date);

  /// Adds a date and time column without an implicit timezone conversion.
  ColumnDefinition dateTime(String name) => _column(name, ColumnType.dateTime);

  /// Adds a timestamp column using the database's timestamp semantics.
  ColumnDefinition timestamp(String name) =>
      _column(name, ColumnType.timestamp);

  /// Adds nullable `created_at` and `updated_at` timestamp columns.
  void timestamps() {
    timestamp('created_at').nullable();
    timestamp('updated_at').nullable();
  }

  /// Adds a binary column.
  ColumnDefinition binary(String name) => _column(name, ColumnType.binary);

  /// Adds a JSON column using the database's native or text representation.
  ColumnDefinition json(String name) => _column(name, ColumnType.json);

  /// Adds a UUID column using the database's native or string representation.
  ColumnDefinition uuid(String name) => _column(name, ColumnType.uuid);

  /// Adds a named non-unique index.
  void index(List<String> columns, {String? name}) =>
      _index(columns, IndexType.normal, name);

  /// Adds a named unique index.
  void unique(List<String> columns, {String? name}) =>
      _index(columns, IndexType.unique, name);

  /// Adds a named primary key, including composite keys.
  void primary(List<String> columns, {String? name}) =>
      _index(columns, IndexType.primary, name);

  /// Adds a foreign key that must be completed with `references(...).on(...)`.
  ForeignKeyDefinition foreign(List<String> columns, {String? name}) {
    final definition = ForeignKeyDefinition(
      name ?? _name(columns, 'foreign'),
      columns,
    );
    _commands.add(definition);
    return definition;
  }

  /// Drops an existing column.
  void dropColumn(String name) =>
      _commands.add(SchemaChangeCommand(SchemaChange.dropColumn, name));

  /// Renames an existing column.
  void renameColumn(String from, String to) =>
      _commands.add(SchemaChangeCommand(SchemaChange.renameColumn, from, to));

  /// Drops an explicitly named index, including a unique index.
  void dropIndex(String name) =>
      _commands.add(SchemaChangeCommand(SchemaChange.dropIndex, name));

  /// Drops an explicitly named foreign key constraint.
  void dropForeign(String name) =>
      _commands.add(SchemaChangeCommand(SchemaChange.dropForeign, name));

  ColumnDefinition _column(
    String name,
    ColumnType type, {
    int? length,
    int? precision,
    int? scale,
    bool autoIncrement = false,
  }) {
    final column = ColumnDefinition(
      name,
      type,
      length: length,
      precision: precision,
      scale: scale,
      autoIncrement: autoIncrement,
    );
    _commands.add(column);
    return column;
  }

  void _index(List<String> columns, IndexType type, String? name) {
    _commands.add(
      IndexDefinition(
        name ?? _name(columns, type == IndexType.normal ? 'index' : type.name),
        columns,
        type,
      ),
    );
  }

  String _name(List<String> columns, String suffix) =>
      '${table.replaceAll('.', '_')}_${columns.join('_')}_$suffix';
}
