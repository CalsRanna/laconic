part of 'mysql_grammar.dart';

mixin _MysqlSchema on SqlGrammar {
  @override
  String quoteSchemaIdentifier(String name, {bool qualified = false}) {
    super.quoteSchemaIdentifier(name, qualified: qualified);
    final parts = qualified ? schemaTableParts(name) : [name];
    return parts.map((p) => '`${p.replaceAll('`', '``')}`').join('.');
  }

  @override
  String compileSchemaLiteral(Object? value) {
    if (value is bool) return value ? '1' : '0';
    if (value is String) {
      // Hex strings preserve quotes and backslashes under either SQL mode.
      final hex =
          utf8
              .encode(value)
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
      return "(convert(x'$hex' using utf8mb4))";
    }
    return super.compileSchemaLiteral(value);
  }

  @override
  String compileColumnType(ColumnDefinition column) {
    switch (column.type) {
      case ColumnType.integer:
        return 'integer';
      case ColumnType.bigInteger:
        return 'bigint';
      case ColumnType.string:
        return 'varchar(${column.length ?? 255})';
      case ColumnType.text:
        return 'text';
      case ColumnType.boolean:
        return 'boolean';
      case ColumnType.decimal:
        return 'decimal(${column.precision ?? 10}, ${column.scale ?? 2})';
      case ColumnType.doublePrecision:
        return 'double';
      case ColumnType.date:
        return 'date';
      case ColumnType.dateTime:
        return 'datetime';
      case ColumnType.timestamp:
        return 'timestamp';
      case ColumnType.binary:
        return 'blob';
      case ColumnType.json:
        return 'json';
      case ColumnType.uuid:
        return 'char(36)';
    }
  }

  @override
  String compileAutoIncrement(ColumnDefinition column) => 'auto_increment';

  @override
  String compileReferentialAction(String action) {
    if (action == 'set default') {
      throw LaconicException(
        'MySQL/MariaDB InnoDB does not support SET DEFAULT foreign keys',
      );
    }
    return super.compileReferentialAction(action);
  }

  @override
  CompiledQuery compileSchemaChange(String table, SchemaChangeCommand command) {
    if (command.change == SchemaChange.dropIndex) {
      return CompiledQuery(
        sql:
            'drop index ${quoteSchemaIdentifier(command.name)} on ${quoteSchemaIdentifier(table, qualified: true)}',
        bindings: [],
      );
    }
    if (command.change == SchemaChange.dropForeign) {
      return CompiledQuery(
        sql:
            'alter table ${quoteSchemaIdentifier(table, qualified: true)} drop foreign key ${quoteSchemaIdentifier(command.name)}',
        bindings: [],
      );
    }
    return super.compileSchemaChange(table, command);
  }

  @override
  CompiledQuery compileTableExists(String table) {
    final parts = schemaTableParts(table);
    return CompiledQuery(
      sql:
          "select table_name from information_schema.tables where table_schema = ${parts.length == 2 ? '?' : 'database()'} and table_name = ? and table_type = 'BASE TABLE'",
      bindings: [if (parts.length == 2) parts.first, parts.last],
    );
  }

  @override
  CompiledQuery compileColumnListing(String table) {
    final parts = schemaTableParts(table);
    return CompiledQuery(
      sql:
          'select column_name as name from information_schema.columns where table_schema = ${parts.length == 2 ? '?' : 'database()'} and table_name = ? order by ordinal_position',
      bindings: [if (parts.length == 2) parts.first, parts.last],
    );
  }
}
