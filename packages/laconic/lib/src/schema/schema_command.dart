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
  computed,
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

  /// The native character set, supported by MySQL and MariaDB.
  String? characterSet;

  /// The native collation name.
  String? collationName;

  /// The column's database comment.
  String? commentText;

  /// Whether an added or changed column should be first in its table.
  bool isFirst = false;

  /// The column after which an added or changed column should appear.
  String? afterColumn;

  /// Whether the default uses the database's current timestamp.
  bool usesCurrentTime = false;

  /// Whether updates automatically refresh this timestamp.
  bool updatesCurrentTime = false;

  /// The trusted SQL expression for a generated or computed column.
  String? generationExpression;

  /// Whether the generated value is stored rather than computed on reads.
  bool isStored = false;

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
    if (isFirst && afterColumn != null) {
      throw LaconicException('first() and after() cannot be combined');
    }
    if ((usesCurrentTime || updatesCurrentTime) &&
        !const [
          ColumnType.dateTime,
          ColumnType.timestamp,
          ColumnType.dateTimeTz,
          ColumnType.timestampTz,
        ].contains(type)) {
      throw LaconicException(
        'Current timestamp modifiers require a date-time or timestamp column',
      );
    }
    if (generationExpression != null) {
      if (generationExpression!.trim().isEmpty ||
          generationExpression!.contains('\u0000')) {
        throw LaconicException(
          'A generated column requires a nonempty SQL expression without NUL',
        );
      }
      if (hasDefault || autoIncrement || updatesCurrentTime || isPrimary) {
        throw LaconicException(
          'Generated columns cannot have defaults, identities, primary keys, or automatic update timestamps',
        );
      }
    }
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
    usesCurrentTime = false;
    defaultValue = value;
    return this;
  }

  /// Sets a native character set on MySQL or MariaDB.
  ColumnDefinition charset(String value) {
    characterSet = value;
    return this;
  }

  /// Sets the database collation for this column.
  ColumnDefinition collation(String value) {
    collationName = value;
    return this;
  }

  /// Sets a column comment on databases with native comment storage.
  ColumnDefinition comment(String value) {
    commentText = value;
    return this;
  }

  /// Places an added or changed column first on MySQL or MariaDB.
  ColumnDefinition first() {
    isFirst = true;
    return this;
  }

  /// Places an added or changed column after [column] on MySQL or MariaDB.
  ColumnDefinition after(String column) {
    afterColumn = column;
    return this;
  }

  /// Defaults this temporal column to the database's current timestamp.
  ColumnDefinition useCurrent() {
    hasDefault = true;
    usesCurrentTime = true;
    return this;
  }

  /// Refreshes this timestamp automatically on MySQL or MariaDB row updates.
  ColumnDefinition useCurrentOnUpdate() {
    updatesCurrentTime = true;
    return this;
  }

  /// Computes a generated column on reads using trusted, unbound SQL.
  ///
  /// Supported by SQLite, MySQL, and MariaDB. For SQL Server use
  /// [Blueprint.computed]; PostgreSQL's supported baseline requires [storedAs].
  ColumnDefinition virtualAs(String expression) {
    generationExpression = expression;
    isStored = false;
    return this;
  }

  /// Stores a generated value computed from trusted, unbound SQL.
  ColumnDefinition storedAs(String expression) {
    generationExpression = expression;
    isStored = true;
    return this;
  }

  /// Persists a SQL Server [Blueprint.computed] column.
  ColumnDefinition persisted([bool value = true]) {
    if (type != ColumnType.computed) {
      throw LaconicException('persisted() requires a computed() column');
    }
    isStored = value;
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

  @override
  ForeignIdColumnDefinition comment(String value) {
    super.comment(value);
    return this;
  }

  @override
  ForeignIdColumnDefinition charset(String value) {
    super.charset(value);
    return this;
  }

  @override
  ForeignIdColumnDefinition collation(String value) {
    super.collation(value);
    return this;
  }

  @override
  ForeignIdColumnDefinition first() {
    super.first();
    return this;
  }

  @override
  ForeignIdColumnDefinition after(String column) {
    super.after(column);
    return this;
  }
}

/// The supported index and key kinds.
enum IndexType { normal, unique, primary, fullText }

/// A named index or primary key over one or more columns.
class IndexDefinition extends SchemaCommand {
  /// The unquoted index or constraint name.
  final String name;

  /// The ordered column names.
  final List<String> columns;

  /// The kind of index or key.
  final IndexType type;

  /// The PostgreSQL text-search configuration for a full-text index.
  String? fullTextLanguage;

  /// Creates an index definition with a snapshot of [columns].
  IndexDefinition(this.name, List<String> columns, this.type)
    : columns = List.unmodifiable(columns);

  /// Selects the PostgreSQL full-text language, defaulting to English.
  ///
  /// Use the same language with `whereFullText()`. Other drivers reject it.
  IndexDefinition language(String value) {
    if (type != IndexType.fullText ||
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) {
      throw LaconicException(
        'language() requires a full-text index and a valid language name',
      );
    }
    fullTextLanguage = value;
    return this;
  }
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
enum SchemaChange {
  dropColumn,
  renameColumn,
  dropIndex,
  dropForeign,
  renameIndex,
  dropPrimary,
  dropFullText,
}

/// An alteration to an existing column, index, or foreign key.
class SchemaChangeCommand extends SchemaCommand {
  /// The alteration kind.
  final SchemaChange change;

  /// The existing object's unquoted name.
  final String name;

  /// The new column or index name for a rename.
  final String? newName;

  /// Creates an alteration command.
  SchemaChangeCommand(this.change, this.name, [this.newName]);
}
