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
}
