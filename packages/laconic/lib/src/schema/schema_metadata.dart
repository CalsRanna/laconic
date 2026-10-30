/// A table or view in a database schema.
class SchemaTable {
  /// The unqualified object name.
  final String name;

  /// The database namespace containing the object.
  final String schema;

  /// The database's definition, when available (for example, a view query).
  final String? definition;

  /// Creates immutable table or view metadata.
  const SchemaTable(this.name, this.schema, {this.definition});

  /// The schema-qualified object name.
  String get qualifiedName => '$schema.$name';
}

/// The database's description of a column, including SQL defaults.
class SchemaColumn {
  /// The unquoted column name.
  final String name;

  /// The database type without length or precision modifiers.
  final String typeName;

  /// The native database type, including exposed length or precision modifiers.
  final String type;

  /// Whether the column accepts SQL NULL.
  final bool nullable;

  /// The database-reported default text, or null when no default exists.
  ///
  /// Literal quoting and expression syntax vary by database.
  final String? defaultValue;

  /// Whether the database generates integer values for this column.
  final bool autoIncrement;

  /// The column collation, when available.
  final String? collation;

  /// The native column comment, when available.
  final String? comment;

  /// The generated-column expression, when available.
  final String? generation;

  /// Whether this is a generated or hidden column excluded from ordinary copies.
  final bool generated;

  /// The default constraint name on databases such as SQL Server.
  final String? defaultConstraint;

  /// The position within a primary key, or zero when not part of one.
  final int primaryPosition;

  /// Creates immutable column metadata.
  const SchemaColumn({
    required this.name,
    required this.typeName,
    required this.type,
    required this.nullable,
    this.defaultValue,
    this.autoIncrement = false,
    this.collation,
    this.comment,
    this.generation,
    this.generated = false,
    this.defaultConstraint,
    this.primaryPosition = 0,
  });
}

/// An index and its ordered key columns.
class SchemaIndex {
  /// The index or constraint name.
  final String name;

  /// The ordered key columns; null represents an expression index key.
  final List<String?> columns;

  /// Whether the index enforces uniqueness.
  final bool unique;

  /// Whether the index implements the primary key.
  final bool primary;

  /// The database index method or kind.
  final String type;

  /// The native SQL index definition or filter predicate, when available.
  ///
  /// SQL Server exposes its filter predicate; SQLite/PostgreSQL expose CREATE SQL.
  final String? definition;

  /// Creates index metadata with an immutable column list.
  SchemaIndex({
    required this.name,
    required List<String?> columns,
    required this.unique,
    required this.primary,
    required this.type,
    this.definition,
  }) : columns = List.unmodifiable(columns);
}

/// A foreign key and its ordered local and referenced columns.
class SchemaForeignKey {
  /// The constraint name, or null when the database does not expose it.
  final String? name;

  /// The ordered local column names.
  final List<String> columns;

  /// The referenced schema, when available.
  final String? foreignSchema;

  /// The unqualified referenced table name.
  final String foreignTable;

  /// The ordered referenced columns; null means an implicit primary-key target.
  final List<String?> foreignColumns;

  /// The normalized update action.
  final String onUpdate;

  /// The normalized delete action.
  final String onDelete;

  /// Creates foreign-key metadata with immutable column lists.
  SchemaForeignKey({
    this.name,
    required List<String> columns,
    this.foreignSchema,
    required this.foreignTable,
    required List<String?> foreignColumns,
    required this.onUpdate,
    required this.onDelete,
  }) : columns = List.unmodifiable(columns),
       foreignColumns = List.unmodifiable(foreignColumns);
}
