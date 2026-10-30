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
      case ColumnType.tinyInteger:
        return 'tinyint';
      case ColumnType.smallInteger:
        return 'smallint';
      case ColumnType.mediumInteger:
        return 'mediumint';
      case ColumnType.integer:
        return 'integer';
      case ColumnType.bigInteger:
        return 'bigint';
      case ColumnType.string:
        return 'varchar(${column.length ?? 255})';
      case ColumnType.char:
        if ((column.length ?? 255) > 255) {
          throw LaconicException('MySQL/MariaDB CHAR length cannot exceed 255');
        }
        return 'char(${column.length ?? 255})';
      case ColumnType.tinyText:
        return 'tinytext';
      case ColumnType.mediumText:
        return 'mediumtext';
      case ColumnType.longText:
        return 'longtext';
      case ColumnType.text:
        return 'text';
      case ColumnType.boolean:
        return 'boolean';
      case ColumnType.decimal:
        return 'decimal(${column.precision ?? 10}, ${column.scale ?? 2})';
      case ColumnType.doublePrecision:
        return 'double';
      case ColumnType.float:
        return 'float(${column.precision ?? 53})';
      case ColumnType.date:
        return 'date';
      case ColumnType.dateTime:
        return 'datetime${compileTemporalPrecision(column)}';
      case ColumnType.timestamp:
        return 'timestamp${compileTemporalPrecision(column)}';
      case ColumnType.time:
        return 'time${compileTemporalPrecision(column)}';
      case ColumnType.year:
        return 'year';
      case ColumnType.dateTimeTz:
      case ColumnType.timestampTz:
      case ColumnType.timeTz:
        throw LaconicException(
          'MySQL/MariaDB has no timezone-aware column type; use explicit UTC dateTime/timestamp storage',
        );
      case ColumnType.binary:
        if (column.length == null) return 'blob';
        if (column.fixed && column.length! > 255 || column.length! > 65535) {
          throw LaconicException(
            'MySQL/MariaDB binary length exceeds the native type limit',
          );
        }
        return '${column.fixed ? 'binary' : 'varbinary'}(${column.length})';
      case ColumnType.json:
      case ColumnType.jsonb:
        return 'json';
      case ColumnType.uuid:
        return 'char(36)';
      case ColumnType.ulid:
        return 'char(26)';
      case ColumnType.enumeration:
      case ColumnType.set:
        final values = column.allowed
            .map((value) {
              if (value.contains('\\')) {
                throw LaconicException(
                  'MySQL/MariaDB enum/set values containing backslashes depend on SQL mode and are not supported',
                );
              }
              return "'${value.replaceAll("'", "''")}'";
            })
            .join(', ');
        return '${column.type == ColumnType.set ? 'set' : 'enum'}($values)';
      case ColumnType.ipAddress:
        return 'varchar(45)';
      case ColumnType.macAddress:
        return 'varchar(17)';
      case ColumnType.geometry:
        return 'geometry';
      case ColumnType.geography:
        throw LaconicException(
          'MySQL/MariaDB does not support geography columns',
        );
      case ColumnType.computed:
        throw LaconicException(
          'MySQL/MariaDB uses typed virtualAs() or storedAs() columns',
        );
    }
  }

  @override
  String compileAutoIncrement(ColumnDefinition column) => 'auto_increment';

  @override
  bool get supportsNativeEnum => true;

  @override
  String compileUnsigned(ColumnDefinition column) =>
      column.isUnsigned ? ' unsigned' : '';

  @override
  String compileColumnCharset(ColumnDefinition column) =>
      column.characterSet == null
          ? ''
          : ' character set ${quoteSchemaIdentifier(column.characterSet!)}';

  @override
  String compileColumnComment(ColumnDefinition column) {
    final comment = column.commentText;
    if (comment == null) return '';
    // COMMENT requires a string literal, not an expression. Backslash escaping
    // changes with SQL mode, so reject it instead of storing different text.
    if (comment.contains('\\') || comment.contains('\u0000')) {
      throw LaconicException(
        'MySQL/MariaDB comments cannot contain backslashes or NUL',
      );
    }
    return " comment '${comment.replaceAll("'", "''")}'";
  }

  @override
  String compileColumnPosition(ColumnDefinition column) =>
      column.isFirst
          ? ' first'
          : column.afterColumn == null
          ? ''
          : ' after ${quoteSchemaIdentifier(column.afterColumn!)}';

  @override
  String compileCurrentTimestamp(ColumnDefinition column) =>
      'current_timestamp${compileTemporalPrecision(column)}';

  @override
  String compileColumnOnUpdate(ColumnDefinition column) =>
      column.updatesCurrentTime
          ? ' on update ${compileCurrentTimestamp(column)}'
          : '';

  @override
  String compileColumnGeneration(ColumnDefinition column) =>
      column.generationExpression == null
          ? ''
          : ' generated always as (${column.generationExpression}) ${column.isStored ? 'stored' : 'virtual'}';

  @override
  CompiledQuery compileSchemaIndex(String table, IndexDefinition index) {
    if (index.fullTextLanguage != null) {
      throw LaconicException(
        'MySQL/MariaDB full-text indexes do not support language()',
      );
    }
    if (index.type != IndexType.fullText) {
      return super.compileSchemaIndex(table, index);
    }
    return CompiledQuery(
      sql:
          'create fulltext index ${quoteSchemaIdentifier(index.name)} on ${quoteSchemaIdentifier(table, qualified: true)} (${compileSchemaColumns(index.columns)})',
      bindings: [],
    );
  }

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
    if (command.change == SchemaChange.dropIndex ||
        command.change == SchemaChange.dropFullText) {
      return CompiledQuery(
        sql:
            'drop index ${quoteSchemaIdentifier(command.name)} on ${quoteSchemaIdentifier(table, qualified: true)}',
        bindings: [],
      );
    }
    if (command.change == SchemaChange.renameIndex) {
      return CompiledQuery(
        sql:
            'alter table ${quoteSchemaIdentifier(table, qualified: true)} rename index ${quoteSchemaIdentifier(command.name)} to ${quoteSchemaIdentifier(command.newName!)}',
        bindings: [],
      );
    }
    if (command.change == SchemaChange.dropPrimary) {
      quoteSchemaIdentifier(command.name);
      return CompiledQuery(
        sql:
            'alter table ${quoteSchemaIdentifier(table, qualified: true)} drop primary key',
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
          '${compileColumnDefinition(column)}${previous.autoIncrement ? ' auto_increment' : ''}${compileColumnPosition(column)}',
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
          "nullif(column_comment, '') as comment, "
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
