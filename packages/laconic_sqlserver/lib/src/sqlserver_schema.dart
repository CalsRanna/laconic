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
      case ColumnType.text:
      case ColumnType.json:
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
      case ColumnType.date:
        return 'date';
      case ColumnType.dateTime:
      case ColumnType.timestamp:
        return 'datetime2';
      case ColumnType.binary:
        return 'varbinary(max)';
      case ColumnType.uuid:
        return 'uniqueidentifier';
    }
  }

  @override
  String compileAutoIncrement(ColumnDefinition column) => 'identity(1,1)';

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
    if (command.change == SchemaChange.renameColumn) {
      quoteSchemaIdentifier(command.newName!);
      return CompiledQuery(
        sql: "exec sp_rename @objname = ?, @newname = ?, @objtype = 'COLUMN'",
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
            'alter table $target alter column $name ${compileColumnType(column)} '
            '${column.isNullable ? 'null' : 'not null'}',
        bindings: [],
      ),
      if (column.hasDefault)
        CompiledQuery(
          sql:
              'alter table $target add default '
              '${compileSchemaLiteral(column.defaultValue)} for $name',
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
