/// @docImport '../grammar/grammar.dart';
/// @docImport 'blueprint.dart';
library;

import '../exception.dart';

/// The column types understood by schema compilers.
///
/// Native support and storage representations vary by driver.
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
  tinyInteger,
  smallInteger,
  mediumInteger,
  char,
  tinyText,
  mediumText,
  longText,
  float,
  dateTimeTz,
  timestampTz,
  time,
  timeTz,
  year,
  jsonb,
  ulid,
  enumeration,
  set,
  ipAddress,
  macAddress,
  geometry,
  geography,
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

  /// The string or binary length, when specified.
  final int? length;

  /// Decimal digits, floating-point precision, or fractional-second precision.
  final int? precision;

  /// The number of fractional decimal digits.
  final int? scale;

  /// Whether the database generates successive integer values.
  final bool autoIncrement;

  /// Whether binary data uses a fixed length.
  final bool fixed;

  /// The immutable allowed values of an enumeration or set.
  final List<String> allowed;

  /// Whether an integer uses the database's native unsigned representation.
  bool isUnsigned = false;

  /// Whether this definition modifies an existing column.
  bool isChange = false;

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
    this.fixed = false,
    List<String> allowed = const [],
  }) : allowed = List.unmodifiable(allowed);

  /// Validates portable type parameters before compiling or executing DDL.
  void validate() {
    if (length != null && length! <= 0) {
      throw LaconicException('Column length must be positive');
    }
    if (fixed && (type != ColumnType.binary || length == null)) {
      throw LaconicException('Fixed binary columns require a length');
    }
    if (type == ColumnType.float &&
        ((precision ?? 53) < 1 || (precision ?? 53) > 53)) {
      throw LaconicException('Float precision must be between 1 and 53');
    }
    if (const [
          ColumnType.time,
          ColumnType.timeTz,
          ColumnType.dateTime,
          ColumnType.dateTimeTz,
          ColumnType.timestamp,
          ColumnType.timestampTz,
        ].contains(type) &&
        precision != null &&
        (precision! < 0 || precision! > 7)) {
      throw LaconicException(
        'Fractional-second precision must be between 0 and 7',
      );
    }
    if (type == ColumnType.enumeration || type == ColumnType.set) {
      if (allowed.isEmpty ||
          allowed.toSet().length != allowed.length ||
          allowed.any((value) => value.contains('\u0000'))) {
        throw LaconicException(
          'Enum/set values must be nonempty, distinct, and contain no NUL',
        );
      }
      if (type == ColumnType.set &&
          (allowed.length > 64 ||
              allowed.any((value) => value.contains(',')))) {
        throw LaconicException(
          'SET supports at most 64 members without commas',
        );
      }
    }
    if ((isUnsigned || autoIncrement) &&
        !const [
          ColumnType.tinyInteger,
          ColumnType.smallInteger,
          ColumnType.mediumInteger,
          ColumnType.integer,
          ColumnType.bigInteger,
        ].contains(type)) {
      throw LaconicException(
        'Unsigned and auto-increment modifiers require an integer type',
      );
    }
  }

  /// Requests a native unsigned integer on MySQL or MariaDB.
  ///
  /// Other drivers reject this modifier instead of silently ignoring it.
  ColumnDefinition unsigned([bool value = true]) {
    isUnsigned = value;
    return this;
  }

  /// Changes an existing column's type, nullability, and default.
  ///
  /// Restate [nullable] and [defaultTo] to keep these modifiers. Existing keys
  /// remain unchanged; use Blueprint key commands to modify indexes separately.
  ColumnDefinition change() {
    isChange = true;
    return this;
  }

  /// Sets whether this column permits nulls.
  ColumnDefinition nullable([bool value = true]) {
    isNullable = value;
    return this;
  }

  /// Sets a literal default or a trusted `Expression()` expression.
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

/// A foreign-key column that can add a constraint to its owning blueprint.
class ForeignIdColumnDefinition extends ColumnDefinition {
  final ForeignKeyDefinition Function(String? name) _foreign;

  /// Creates a foreign column whose constraint is registered by [foreign].
  ForeignIdColumnDefinition(
    super.name,
    super.type,
    ForeignKeyDefinition Function(String? name) foreign,
  ) : _foreign = foreign;

  /// Adds a foreign key to an explicitly named table and referenced column.
  ///
  /// Apply column modifiers before calling this method. Table names are explicit
  /// because Laconic does not provide model metadata or language inflection.
  ForeignKeyDefinition constrained(
    String table, {
    String column = 'id',
    String? name,
  }) => references(column, name: name).on(table);

  /// Adds a foreign key whose target table must be supplied with `on()`.
  ForeignKeyDefinition references(String column, {String? name}) =>
      _foreign(name).references([column]);

  @override
  ForeignIdColumnDefinition nullable([bool value = true]) {
    super.nullable(value);
    return this;
  }

  @override
  ForeignIdColumnDefinition defaultTo(Object? value) {
    super.defaultTo(value);
    return this;
  }

  @override
  ForeignIdColumnDefinition unsigned([bool value = true]) {
    super.unsigned(value);
    return this;
  }

  @override
  ForeignIdColumnDefinition primary() {
    super.primary();
    return this;
  }

  @override
  ForeignIdColumnDefinition unique() {
    super.unique();
    return this;
  }

  @override
  ForeignIdColumnDefinition change() {
    super.change();
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

  /// Cascades deletion to referencing rows.
  ForeignKeyDefinition cascadeOnDelete() => onDelete('cascade');

  /// Cascades updates of the referenced key.
  ForeignKeyDefinition cascadeOnUpdate() => onUpdate('cascade');

  /// Sets referencing columns to null on deletion.
  ForeignKeyDefinition nullOnDelete() => onDelete('set null');

  /// Sets referencing columns to null on key updates.
  ForeignKeyDefinition nullOnUpdate() => onUpdate('set null');

  /// Restricts deletion of referenced rows where supported.
  ForeignKeyDefinition restrictOnDelete() => onDelete('restrict');

  /// Restricts updates of referenced keys where supported.
  ForeignKeyDefinition restrictOnUpdate() => onUpdate('restrict');

  /// Uses the database's NO ACTION behavior on deletion.
  ForeignKeyDefinition noActionOnDelete() => onDelete('no action');

  /// Uses the database's NO ACTION behavior on key updates.
  ForeignKeyDefinition noActionOnUpdate() => onUpdate('no action');

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
