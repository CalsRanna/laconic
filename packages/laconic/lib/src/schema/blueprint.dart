/// @docImport '../grammar/grammar.dart';
library;

import '../exception.dart';

/// The portable column types understood by schema compilers.
enum ColumnType {
  integer,
  bigInteger,
  string,
  text,
  boolean,
  decimal,
  doublePrecision,
  date,
  dateTime,
  timestamp,
  binary,
  json,
  uuid,
}

/// A table definition command consumed by [SqlGrammar].
///
/// Concrete commands describe columns, indexes, foreign keys, or alterations.
sealed class SchemaCommand {}

/// A column definition with fluent nullability, default, and key modifiers.
class ColumnDefinition extends SchemaCommand {
  /// The unquoted column name.
  final String name;

  /// The portable SQL type.
  final ColumnType type;

  /// The maximum string length.
  final int? length;

  /// The total number of decimal digits.
  final int? precision;

  /// The number of fractional decimal digits.
  final int? scale;

  /// Whether the database generates successive integer values.
  final bool autoIncrement;

  /// Whether the column permits nulls.
  bool isNullable = false;

  /// Whether the column is a primary key.
  bool isPrimary = false;

  /// Whether the column has a unique constraint.
  bool isUnique = false;

  /// Whether a default was explicitly specified, including `null`.
  bool hasDefault = false;

  /// The literal default or trusted raw SQL expression.
  Object? defaultValue;

  /// Creates a column definition for a schema compiler.
  ColumnDefinition(
    this.name,
    this.type, {
    this.length,
    this.precision,
    this.scale,
    this.autoIncrement = false,
  });

  /// Sets whether this column permits nulls.
  ColumnDefinition nullable([bool value = true]) {
    isNullable = value;
    return this;
  }

  /// Sets a literal default or a trusted `raw()` expression.
  ColumnDefinition defaultTo(Object? value) {
    hasDefault = true;
    defaultValue = value;
    return this;
  }

  /// Marks this column as the primary key.
  ColumnDefinition primary() {
    isPrimary = true;
    return this;
  }

  /// Adds an inline unique constraint.
  ///
  /// Use [Blueprint.unique] for a named index that can later be dropped.
  ColumnDefinition unique() {
    isUnique = true;
    return this;
  }
}

/// The supported index and key kinds.
enum IndexType { normal, unique, primary }

/// A named index or primary key over one or more columns.
class IndexDefinition extends SchemaCommand {
  /// The unquoted index or constraint name.
  final String name;

  /// The ordered column names.
  final List<String> columns;

  /// The kind of index or key.
  final IndexType type;

  /// Creates an index definition with a snapshot of [columns].
  IndexDefinition(this.name, List<String> columns, this.type)
    : columns = List.unmodifiable(columns);
}

/// A named foreign key with explicit referenced table and columns.
class ForeignKeyDefinition extends SchemaCommand {
  /// The unquoted constraint name.
  final String name;

  /// The local column names.
  final List<String> columns;

  /// The referenced column names.
  List<String> referencedColumns = const [];

  /// The referenced table, optionally qualified by a schema.
  String? referencedTable;

  /// The action performed when a referenced row is deleted.
  String? deleteAction;

  /// The action performed when a referenced key is updated.
  String? updateAction;

  /// Creates a foreign key over [columns].
  ForeignKeyDefinition(this.name, List<String> columns)
    : columns = List.unmodifiable(columns);

  /// Sets the referenced columns.
  ForeignKeyDefinition references(List<String> columns) {
    referencedColumns = List.unmodifiable(columns);
    return this;
  }

  /// Sets the referenced table.
  ForeignKeyDefinition on(String table) {
    referencedTable = table;
    return this;
  }

  /// Sets a referential action for deletion.
  ForeignKeyDefinition onDelete(String action) {
    deleteAction = _action(action);
    return this;
  }

  /// Sets a referential action for updates.
  ForeignKeyDefinition onUpdate(String action) {
    updateAction = _action(action);
    return this;
  }

  String _action(String value) {
    final action = value.toLowerCase();
    if (!const [
      'cascade',
      'restrict',
      'no action',
      'set null',
      'set default',
    ].contains(action)) {
      throw LaconicException('Unsupported foreign key action: $value');
    }
    return action;
  }
}

/// The alterations that operate on existing named objects.
enum SchemaChange { dropColumn, renameColumn, dropIndex, dropForeign }

/// An alteration to an existing column, index, or foreign key.
class SchemaChangeCommand extends SchemaCommand {
  /// The alteration kind.
  final SchemaChange change;

  /// The existing object's unquoted name.
  final String name;

  /// The new column name for a rename.
  final String? newName;

  /// Creates an alteration command.
  SchemaChangeCommand(this.change, this.name, [this.newName]);
}

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
