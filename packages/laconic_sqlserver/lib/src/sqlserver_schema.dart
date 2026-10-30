part of 'sqlserver_grammar.dart';

mixin _SqlserverSchema on SqlGrammar {
  @override
  bool get supportsSchemaTransactions => true;

  @override
  String quoteSchemaIdentifier(String name, {bool qualified = false}) {
    super.quoteSchemaIdentifier(name, qualified: qualified);
    final parts = qualified ? schemaTableParts(name) : [name];
    return parts.map((p) => '[${p.replaceAll(']', ']]')}]').join('.');
  }

  @override
  String compileSchemaLiteral(Object? value) {
    if (value is bool) return value ? '1' : '0';
    if (value is String) return 'N${super.compileSchemaLiteral(value)}';
    return super.compileSchemaLiteral(value);
  }

  @override
  String compileColumnType(ColumnDefinition column) {
    switch (column.type) {
      case ColumnType.tinyInteger:
        return 'tinyint';
      case ColumnType.smallInteger:
      case ColumnType.year:
        return 'smallint';
      case ColumnType.mediumInteger:
      case ColumnType.integer:
        return 'int';
      case ColumnType.bigInteger:
        return 'bigint';
      case ColumnType.string:
        if ((column.length ?? 255) > 4000) {
          throw LaconicException(
            'SQL Server strings are limited to 4000 characters; use text()',
          );
        }
        return 'nvarchar(${column.length ?? 255})';
      case ColumnType.char:
        if ((column.length ?? 255) > 4000) {
          throw LaconicException('SQL Server NCHAR length cannot exceed 4000');
        }
        return 'nchar(${column.length ?? 255})';
      case ColumnType.tinyText:
      case ColumnType.mediumText:
      case ColumnType.longText:
      case ColumnType.enumeration:
      case ColumnType.text:
      case ColumnType.json:
      case ColumnType.jsonb:
        return 'nvarchar(max)';
      case ColumnType.boolean:
        return 'bit';
      case ColumnType.decimal:
        if ((column.precision ?? 10) > 38) {
          throw LaconicException(
            'SQL Server decimal precision cannot exceed 38',
          );
        }
        return 'decimal(${column.precision ?? 10}, ${column.scale ?? 2})';
      case ColumnType.doublePrecision:
        return 'float';
      case ColumnType.float:
        return 'float(${column.precision ?? 53})';
      case ColumnType.date:
        return 'date';
      case ColumnType.dateTime:
      case ColumnType.timestamp:
        return 'datetime2${compileTemporalPrecision(column, maximum: 7)}';
      case ColumnType.dateTimeTz:
      case ColumnType.timestampTz:
        return 'datetimeoffset${compileTemporalPrecision(column, maximum: 7)}';
      case ColumnType.time:
        return 'time${compileTemporalPrecision(column, maximum: 7)}';
      case ColumnType.timeTz:
        throw LaconicException(
          'SQL Server does not support TIME WITH TIME ZONE',
        );
      case ColumnType.binary:
        if (column.length != null && column.length! > 8000) {
          throw LaconicException(
            'SQL Server binary length cannot exceed 8000; omit length for varbinary(max)',
          );
        }
        return '${column.fixed ? 'binary' : 'varbinary'}(${column.length ?? 'max'})';
      case ColumnType.uuid:
        return 'uniqueidentifier';
      case ColumnType.ulid:
        return 'char(26)';
      case ColumnType.ipAddress:
        return 'nvarchar(45)';
      case ColumnType.macAddress:
        return 'nvarchar(17)';
      case ColumnType.set:
        throw LaconicException('SQL Server does not support SET columns');
      case ColumnType.geometry:
        return 'geometry';
      case ColumnType.geography:
        return 'geography';
      case ColumnType.computed:
        throw LaconicException(
          'SQL Server infers computed column types from their expressions',
        );
    }
  }

  @override
  String compileAutoIncrement(ColumnDefinition column) => 'identity(1,1)';

  @override
  String compileColumnCollation(ColumnDefinition column) {
    final collation = column.collationName;
    if (collation == null) return '';
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(collation)) {
      throw LaconicException('Invalid SQL Server collation name: $collation');
    }
    return ' collate $collation';
  }

  @override
  String compileColumnDefinition(ColumnDefinition column) {
    if (column.type != ColumnType.computed) {
      return super.compileColumnDefinition(column);
    }
    column.validate();
    compileColumnPosition(column);
    compileColumnCharset(column);
    compileUnsigned(column);
    if (column.generationExpression == null ||
        column.collationName != null ||
        !column.isStored && !column.isNullable) {
      throw LaconicException(
        'computed() requires an expression; put COLLATE in the expression and use persisted() for NOT NULL',
      );
    }
    return '${quoteSchemaIdentifier(column.name)} as (${column.generationExpression})'
        '${column.isStored ? ' persisted${column.isNullable ? '' : ' not null'}' : ''}'
        '${column.isUnique ? ' unique' : ''}';
  }

  @override
  String compileColumnComment(ColumnDefinition column) => '';

  @override
  List<CompiledQuery> compileColumnExtras(
    String table,
    ColumnDefinition column,
  ) {
    if (column.commentText == null && !column.isChange) return [];
    final parts = schemaTableParts(table);
    const arguments =
        "@name=N'MS_Description', @level0type=N'SCHEMA', @level0name=@schema, @level1type=N'TABLE', @level1name=@table, @level2type=N'COLUMN', @level2name=@column";
    final exists =
        "exists (select 1 from sys.extended_properties p join sys.tables t on t.object_id = p.major_id join sys.schemas s on s.schema_id = t.schema_id join sys.columns c on c.object_id = t.object_id and c.column_id = p.minor_id where p.class = 1 and p.name = N'MS_Description' and s.name = @schema and t.name = @table and c.name = @column)";
    return [
      CompiledQuery(
        sql:
            'declare @schema sysname = ${parts.length == 2 ? '?' : 'schema_name()'}; declare @table sysname = ?; declare @column sysname = ?; '
            '${column.commentText == null ? 'if $exists exec sys.sp_dropextendedproperty $arguments' : 'declare @value nvarchar(4000) = ?; if $exists exec sys.sp_updateextendedproperty $arguments, @value=@value; else exec sys.sp_addextendedproperty $arguments, @value=@value'}',
        bindings: [
          if (parts.length == 2) parts.first,
          parts.last,
          column.name,
          if (column.commentText != null) column.commentText,
        ],
      ),
    ];
  }

  @override
  String compileReferentialAction(String action) {
    if (action == 'restrict') {
      throw LaconicException(
        'SQL Server does not support RESTRICT; use NO ACTION',
      );
    }
    return super.compileReferentialAction(action);
  }

  @override
  CompiledQuery compileAddColumn(
    String table,
    ColumnDefinition column,
  ) => CompiledQuery(
    sql:
        'alter table ${quoteSchemaIdentifier(table, qualified: true)} add ${compileColumnDefinition(column)}',
    bindings: [],
  );

  @override
  CompiledQuery compileSchemaChange(String table, SchemaChangeCommand command) {
    if (command.change == SchemaChange.dropIndex) {
      return CompiledQuery(
        sql:
            'drop index ${quoteSchemaIdentifier(command.name)} on ${quoteSchemaIdentifier(table, qualified: true)}',
        bindings: [],
      );
    }
    if (command.change == SchemaChange.renameColumn ||
        command.change == SchemaChange.renameIndex) {
      quoteSchemaIdentifier(command.newName!);
      return CompiledQuery(
        sql:
            "exec sp_rename @objname = ?, @newname = ?, @objtype = '${command.change == SchemaChange.renameIndex ? 'INDEX' : 'COLUMN'}'",
        bindings: [
          '${quoteSchemaIdentifier(table, qualified: true)}.${quoteSchemaIdentifier(command.name)}',
          command.newName,
        ],
      );
    }
    return super.compileSchemaChange(table, command);
  }

  @override
  List<CompiledQuery> compileRenameTable(String from, String to) {
    if (schemaTableParts(to).length != 1) {
      throw LaconicException('The new table name must be unqualified');
    }
    return [
      CompiledQuery(
        sql: "exec sp_rename @objname = ?, @newname = ?, @objtype = 'OBJECT'",
        bindings: [quoteSchemaIdentifier(from, qualified: true), to],
      ),
    ];
  }

  @override
  CompiledQuery compileTableExists(String table) => CompiledQuery(
    sql: "select name from sys.tables where object_id = object_id(?, 'U')",
    bindings: [quoteSchemaIdentifier(table, qualified: true)],
  );

  @override
  CompiledQuery compileColumnListing(String table) => CompiledQuery(
    sql:
        "select name from sys.columns where object_id = object_id(?, 'U') order by column_id",
    bindings: [quoteSchemaIdentifier(table, qualified: true)],
  );

  @override
  List<CompiledQuery> compileChangeColumn(
    String table,
    ColumnDefinition column,
    SchemaColumn previous,
  ) {
    final target = quoteSchemaIdentifier(table, qualified: true);
    final name = quoteSchemaIdentifier(column.name);
    return [
      if (previous.defaultConstraint != null)
        CompiledQuery(
          sql:
              'alter table $target drop constraint ${quoteSchemaIdentifier(previous.defaultConstraint!)}',
          bindings: [],
        ),
      CompiledQuery(
        sql:
            'alter table $target alter column $name ${compileColumnType(column)}${compileColumnCollation(column)} '
            '${column.isNullable ? 'null' : 'not null'}',
        bindings: [],
      ),
      if (column.hasDefault)
        CompiledQuery(
          sql:
              'alter table $target add default '
              '${compileColumnDefault(column)} for $name',
          bindings: [],
        ),
    ];
  }

  @override
  CompiledQuery compileTables({String? schema}) => CompiledQuery(
    sql:
        'select t.name, s.name as [schema] from sys.tables t join sys.schemas s on s.schema_id = t.schema_id '
        'where t.is_ms_shipped = 0 and s.name = ${schema == null ? 'schema_name()' : '?'} order by t.name',
    bindings: [if (schema != null) schema],
  );

  @override
  CompiledQuery compileViews({String? schema}) => CompiledQuery(
    sql:
        'select v.name, s.name as [schema], object_definition(v.object_id) as definition '
        'from sys.views v join sys.schemas s on s.schema_id = v.schema_id '
        'where v.is_ms_shipped = 0 and s.name = ${schema == null ? 'schema_name()' : '?'} order by v.name',
    bindings: [if (schema != null) schema],
  );

  @override
  CompiledQuery compileColumns(String table) => CompiledQuery(
    sql:
        "select c.name, t.name as type_name, t.name + case "
        "when t.name in ('nvarchar','nchar') then '(' + case when c.max_length = -1 then 'max' else cast(c.max_length / 2 as varchar(10)) end + ')' "
        "when t.name in ('varchar','char','varbinary','binary') then '(' + case when c.max_length = -1 then 'max' else cast(c.max_length as varchar(10)) end + ')' "
        "when t.name in ('decimal','numeric') then '(' + cast(c.precision as varchar(10)) + ',' + cast(c.scale as varchar(10)) + ')' "
        "else '' end as type, c.is_nullable as nullable, d.definition as default_value, "
        "c.is_identity as auto_increment, c.collation_name as collation, cc.definition as generation, c.is_computed as generated, "
        "cast((select p.value from sys.extended_properties p where p.class = 1 and p.major_id = c.object_id and p.minor_id = c.column_id and p.name = N'MS_Description') as nvarchar(4000)) as comment, "
        "d.name as default_constraint, coalesce((select ic.key_ordinal from sys.indexes i "
        "join sys.index_columns ic on ic.object_id = i.object_id and ic.index_id = i.index_id "
        "where i.object_id = c.object_id and i.is_primary_key = 1 and ic.column_id = c.column_id), 0) as primary_position "
        "from sys.columns c join sys.types t on t.user_type_id = c.user_type_id "
        "left join sys.default_constraints d on d.object_id = c.default_object_id "
        "left join sys.computed_columns cc on cc.object_id = c.object_id and cc.column_id = c.column_id "
        "where c.object_id = object_id(?, 'U') order by c.column_id",
    bindings: [quoteSchemaIdentifier(table, qualified: true)],
  );

  @override
  CompiledQuery compileIndexes(String table) => CompiledQuery(
    sql:
        "select i.name, c.name as column_name, ic.key_ordinal as position, i.is_unique, i.is_primary_key as is_primary, "
        "lower(i.type_desc) as type, i.filter_definition as definition from sys.indexes i "
        "join sys.index_columns ic on ic.object_id = i.object_id and ic.index_id = i.index_id "
        "join sys.columns c on c.object_id = ic.object_id and c.column_id = ic.column_id "
        "where i.object_id = object_id(?, 'U') and i.is_hypothetical = 0 and ic.key_ordinal > 0 "
        "order by i.name, ic.key_ordinal",
    bindings: [quoteSchemaIdentifier(table, qualified: true)],
  );

  @override
  CompiledQuery compileForeignKeys(String table) => CompiledQuery(
    sql:
        "select f.name, c.name as column_name, k.constraint_column_id as position, "
        "schema_name(ft.schema_id) as foreign_schema, ft.name as foreign_table, fc.name as foreign_column, "
        "f.update_referential_action_desc as on_update, f.delete_referential_action_desc as on_delete "
        "from sys.foreign_keys f join sys.foreign_key_columns k on k.constraint_object_id = f.object_id "
        "join sys.columns c on c.object_id = k.parent_object_id and c.column_id = k.parent_column_id "
        "join sys.tables ft on ft.object_id = k.referenced_object_id "
        "join sys.columns fc on fc.object_id = k.referenced_object_id and fc.column_id = k.referenced_column_id "
        "where f.parent_object_id = object_id(?, 'U') order by f.name, k.constraint_column_id",
    bindings: [quoteSchemaIdentifier(table, qualified: true)],
  );
}
