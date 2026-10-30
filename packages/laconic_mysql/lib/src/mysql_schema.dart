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

  @override
  List<CompiledQuery> compileChangeColumn(
    String table,
    ColumnDefinition column,
    SchemaColumn previous,
  ) => [
    CompiledQuery(
      sql:
          'alter table ${quoteSchemaIdentifier(table, qualified: true)} modify column '
          '${compileColumnDefinition(column)}${previous.autoIncrement ? ' auto_increment' : ''}',
      bindings: [],
    ),
  ];

  @override
  CompiledQuery compileTables({String? schema}) =>
      _schemaTables('BASE TABLE', schema);

  @override
  CompiledQuery compileViews({String? schema}) => CompiledQuery(
    sql:
        'select table_name as name, table_schema as `schema`, view_definition as definition '
        'from information_schema.views where table_schema = ${schema == null ? 'database()' : '?'} order by table_name',
    bindings: [if (schema != null) schema],
  );

  CompiledQuery _schemaTables(String type, String? schema) => CompiledQuery(
    sql:
        'select table_name as name, table_schema as `schema` from information_schema.tables '
        'where table_type = ? and table_schema = ${schema == null ? 'database()' : '?'} order by table_name',
    bindings: [type, if (schema != null) schema],
  );

  @override
  CompiledQuery compileColumns(String table) {
    final parts = schemaTableParts(table);
    return CompiledQuery(
      sql:
          "select column_name as name, data_type as type_name, column_type as type, "
          "is_nullable = 'YES' as nullable, column_default as default_value, "
          "extra like '%auto_increment%' as auto_increment, collation_name as collation, "
          "nullif(generation_expression, '') as generation, generation_expression <> '' as `generated`, "
          "coalesce((select k.ordinal_position from information_schema.key_column_usage k "
          "where k.table_schema = c.table_schema and k.table_name = c.table_name "
          "and k.column_name = c.column_name and k.constraint_name = 'PRIMARY'), 0) as primary_position "
          "from information_schema.columns c where table_schema = ${parts.length == 2 ? '?' : 'database()'} "
          "and table_name = ? order by ordinal_position",
      bindings: [if (parts.length == 2) parts.first, parts.last],
    );
  }

  @override
  CompiledQuery compileIndexes(String table) {
    final parts = schemaTableParts(table);
    return CompiledQuery(
      sql:
          "select index_name as name, column_name as column_name, seq_in_index as position, "
          "non_unique = 0 as is_unique, index_name = 'PRIMARY' as is_primary, lower(index_type) as type "
          "from information_schema.statistics where table_schema = ${parts.length == 2 ? '?' : 'database()'} "
          "and table_name = ? order by index_name, seq_in_index",
      bindings: [if (parts.length == 2) parts.first, parts.last],
    );
  }

  @override
  CompiledQuery compileForeignKeys(String table) {
    final parts = schemaTableParts(table);
    return CompiledQuery(
      sql:
          'select k.constraint_name as name, k.column_name as column_name, k.ordinal_position as position, '
          'k.referenced_table_schema as foreign_schema, k.referenced_table_name as foreign_table, '
          'k.referenced_column_name as foreign_column, r.update_rule as on_update, r.delete_rule as on_delete '
          'from information_schema.key_column_usage k join information_schema.referential_constraints r '
          'on r.constraint_schema = k.constraint_schema and r.constraint_name = k.constraint_name '
          'and r.table_name = k.table_name '
          'where k.table_schema = ${parts.length == 2 ? '?' : 'database()'} and k.table_name = ? '
          'and k.referenced_table_name is not null order by k.constraint_name, k.ordinal_position',
      bindings: [if (parts.length == 2) parts.first, parts.last],
    );
  }
}
