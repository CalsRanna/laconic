/// @docImport '../grammar/grammar.dart';
/// @docImport 'blueprint.dart';
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
