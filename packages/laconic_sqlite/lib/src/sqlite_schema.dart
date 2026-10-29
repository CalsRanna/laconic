part of 'sqlite_grammar.dart';

mixin _SqliteSchema on SqlGrammar {
  @override
  bool get supportsSchemaTransactions => true;

  @override
  String compileColumnType(ColumnDefinition column) {
    switch (column.type) {
      case ColumnType.integer:
      case ColumnType.bigInteger:
        return 'integer';
      case ColumnType.string:
        return 'varchar(${column.length ?? 255})';
      case ColumnType.text:
      case ColumnType.json:
      case ColumnType.date:
      case ColumnType.dateTime:
      case ColumnType.timestamp:
        return 'text';
      case ColumnType.boolean:
        return 'boolean';
      case ColumnType.decimal:
        return 'numeric';
      case ColumnType.doublePrecision:
        return 'real';
      case ColumnType.binary:
        return 'blob';
      case ColumnType.uuid:
        return 'varchar(36)';
    }
  }

  @override
  String compileAutoIncrement(ColumnDefinition column) => '';

  @override
  String compileColumnDefinition(ColumnDefinition column) {
    final compiled = super.compileColumnDefinition(column);
    if (!column.autoIncrement) return compiled;
    return '${quoteSchemaIdentifier(column.name)} integer primary key autoincrement${column.isUnique ? ' unique' : ''}';
  }

  @override
  List<CompiledQuery> compileAlterTable(Blueprint blueprint) {
    for (final command in blueprint.commands) {
      if (command is ForeignKeyDefinition ||
          command is IndexDefinition && command.type == IndexType.primary ||
          command is SchemaChangeCommand &&
              command.change == SchemaChange.dropForeign) {
        throw LaconicException(
          'SQLite cannot alter primary/foreign keys without rebuilding the table',
        );
      }
    }
    return super.compileAlterTable(blueprint);
  }

  @override
  CompiledQuery compileAddColumn(String table, ColumnDefinition column) {
    if (column.isPrimary ||
        column.isUnique ||
        column.autoIncrement ||
        column.hasDefault && column.defaultValue is Expression) {
      throw LaconicException(
        'SQLite ADD COLUMN does not support keys or expression defaults',
      );
    }
    return super.compileAddColumn(table, column);
  }

  @override
  String compileForeignKey(ForeignKeyDefinition key) {
    if (key.referencedTable != null &&
        schemaTableParts(key.referencedTable!).length != 1) {
      throw LaconicException(
        'SQLite foreign keys require an unqualified referenced table',
      );
    }
    return super.compileForeignKey(key);
  }

  @override
  CompiledQuery compileSchemaIndex(String table, IndexDefinition index) {
    final parts = schemaTableParts(table);
    final prefix =
        parts.length == 2 ? '${quoteSchemaIdentifier(parts.first)}.' : '';
    return CompiledQuery(
      sql:
          'create ${index.type == IndexType.unique ? 'unique ' : ''}index $prefix${quoteSchemaIdentifier(index.name)} on ${quoteSchemaIdentifier(parts.last)} (${compileSchemaColumns(index.columns)})',
      bindings: [],
    );
  }

  @override
  CompiledQuery compileTableExists(String table) {
    final parts = schemaTableParts(table);
    final schema = quoteSchemaIdentifier(
      parts.length == 2 ? parts.first : 'main',
    );
    return CompiledQuery(
      sql:
          "select name from $schema.sqlite_master where type = 'table' and name = ?",
      bindings: [parts.last],
    );
  }

  @override
  CompiledQuery compileColumnListing(String table) {
    final parts = schemaTableParts(table);
    return CompiledQuery(
      sql: 'select name from pragma_table_xinfo(?, ?) order by cid',
      bindings: [parts.last, parts.length == 2 ? parts.first : 'main'],
    );
  }
}
