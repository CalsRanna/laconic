part of 'sqlite_grammar.dart';

mixin _SqliteSchema on SqlGrammar {
  @override
  bool get supportsTemporaryTables => true;

  @override
  String schemaTemporaryTableName(String table) {
    final parts = schemaTableParts(table);
    if (parts.length == 2 && parts.first != 'temp') {
      throw LaconicException('SQLite temporary tables use the temp schema');
    }
    return 'temp.${parts.last}';
  }

  @override
  List<CompiledQuery> compileDropTemporaryTable(
    String table, {
    bool ifExists = false,
  }) => compileDropTable(schemaTemporaryTableName(table), ifExists: ifExists);

  @override
  bool get supportsSchemaTransactions => true;

  @override
  bool get requiresSchemaTransactionForDropAllTables => true;

  @override
  List<CompiledQuery> compileDropAllTables(
    List<SchemaTable> tables,
    Map<String, List<SchemaForeignKey>> foreignKeys,
  ) => [
    // Dropping a virtual table also removes its shadow tables.
    for (final table in [...tables]..sort((a, b) {
      final aVirtual =
          a.definition?.toLowerCase().startsWith('create virtual') ?? false;
      final bVirtual =
          b.definition?.toLowerCase().startsWith('create virtual') ?? false;
      return (aVirtual ? 0 : 1).compareTo(bVirtual ? 0 : 1);
    }))
      ...compileDropTable(table.qualifiedName, ifExists: true),
  ];

  @override
  String compileColumnType(ColumnDefinition column) {
    switch (column.type) {
      case ColumnType.tinyInteger:
      case ColumnType.smallInteger:
      case ColumnType.mediumInteger:
      case ColumnType.year:
      case ColumnType.integer:
      case ColumnType.bigInteger:
        return 'integer';
      case ColumnType.string:
        return 'varchar(${column.length ?? 255})';
      case ColumnType.char:
        return 'char(${column.length ?? 255})';
      case ColumnType.tinyText:
      case ColumnType.mediumText:
      case ColumnType.longText:
      case ColumnType.enumeration:
      case ColumnType.text:
      case ColumnType.json:
      case ColumnType.jsonb:
      case ColumnType.date:
      case ColumnType.dateTime:
      case ColumnType.dateTimeTz:
      case ColumnType.timestamp:
      case ColumnType.timestampTz:
      case ColumnType.time:
      case ColumnType.timeTz:
        return 'text';
      case ColumnType.boolean:
        return 'boolean';
      case ColumnType.decimal:
        return 'numeric';
      case ColumnType.doublePrecision:
      case ColumnType.float:
        return 'real';
      case ColumnType.binary:
        if (column.length != null || column.fixed) {
          throw LaconicException(
            'SQLite BLOB does not support a fixed or maximum length',
          );
        }
        return 'blob';
      case ColumnType.uuid:
        return 'varchar(36)';
      case ColumnType.ulid:
        return 'char(26)';
      case ColumnType.ipAddress:
        return 'varchar(45)';
      case ColumnType.macAddress:
        return 'varchar(17)';
      case ColumnType.set:
      case ColumnType.geometry:
      case ColumnType.geography:
        throw LaconicException(
          'SQLite does not support ${column.type.name} columns',
        );
      case ColumnType.computed:
        throw LaconicException(
          'SQLite uses typed virtualAs() or storedAs() columns',
        );
    }
  }

  @override
  String compileAutoIncrement(ColumnDefinition column) => '';

  @override
  String compileColumnGeneration(ColumnDefinition column) =>
      column.generationExpression == null
          ? ''
          : ' generated always as (${column.generationExpression}) ${column.isStored ? 'stored' : 'virtual'}';

  @override
  String compileColumnDefinition(ColumnDefinition column) {
    final compiled = super.compileColumnDefinition(column);
    if (!column.autoIncrement) return compiled;
    return '${quoteSchemaIdentifier(column.name)} integer primary key autoincrement${column.isUnique ? ' unique' : ''}';
  }

  @override
  bool requiresTableRebuild(Blueprint blueprint) => blueprint.commands.any(
    (command) =>
        command is ColumnDefinition &&
            (command.isChange ||
                command.isPrimary ||
                command.isUnique ||
                command.autoIncrement ||
                command.isStored ||
                command.usesCurrentTime ||
                command.hasDefault && command.defaultValue is Expression) ||
        command is ForeignKeyDefinition ||
        command is IndexDefinition && command.type == IndexType.primary ||
        command is SchemaChangeCommand &&
            (command.change == SchemaChange.dropColumn ||
                command.change == SchemaChange.dropPrimary ||
                command.change == SchemaChange.dropForeign),
  );

  @override
  bool requiresSchemaSnapshot(Blueprint blueprint) =>
      requiresTableRebuild(blueprint) ||
      blueprint.commands.any(
        (c) => c is SchemaChangeCommand && c.change == SchemaChange.renameIndex,
      );

  @override
  bool requiresSchemaTransaction(Blueprint blueprint) =>
      requiresSchemaSnapshot(blueprint);

  @override
  List<CompiledQuery> compileAlterTable(
    Blueprint blueprint, {
    List<SchemaColumn> columns = const [],
    List<Map<String, Object?>> objects = const [],
  }) {
    final options = compileAlterTableOptions(blueprint);
    if (requiresTableRebuild(blueprint)) {
      return [
        ..._SqliteTableRebuild(this, blueprint, columns, objects).compile(),
        ...options,
      ];
    }
    if (requiresSchemaSnapshot(blueprint)) {
      final name = schemaTableParts(blueprint.table).last;
      final indexes = [
        for (final o in objects)
          if (o['type'] == 'index' && o['tbl_name'] == name && o['sql'] != null)
            Map<String, Object?>.of(o),
      ];
      final statements = <CompiledQuery>[];
      for (final command in blueprint.commands) {
        if (command is ColumnDefinition) {
          statements.add(compileAddColumn(blueprint.table, command));
        } else if (command is IndexDefinition) {
          final query = compileSchemaIndex(blueprint.table, command);
          statements.add(query);
          indexes.add({'name': command.name, 'sql': query.sql});
        } else if (command is SchemaChangeCommand) {
          if (command.change == SchemaChange.renameIndex) {
            final sql = _SqliteTableRebuild.renameIndex(
              this,
              blueprint.table,
              indexes,
              command,
            );
            statements.add(
              compileSchemaChange(
                blueprint.table,
                SchemaChangeCommand(SchemaChange.dropIndex, command.name),
              ),
            );
            statements.add(CompiledQuery(sql: sql, bindings: []));
          } else {
            statements.add(compileSchemaChange(blueprint.table, command));
            if (command.change == SchemaChange.dropIndex) {
              indexes.removeWhere((i) => i['name'] == command.name);
            }
            if (command.change == SchemaChange.renameColumn) {
              // Native ALTER TABLE rewrites dependent expressions. Mixing it
              // with index snapshots would replay the old column names.
              throw LaconicException(
                'Use separate SQLite table() calls for renameColumn() and renameIndex()',
              );
            }
          }
        }
      }
      return [...statements, ...options];
    }
    return super.compileAlterTable(
      blueprint,
      columns: columns,
      objects: objects,
    );
  }

  @override
  CompiledQuery compileAddColumn(String table, ColumnDefinition column) {
    if (column.isPrimary ||
        column.isUnique ||
        column.autoIncrement ||
        column.isStored ||
        column.usesCurrentTime ||
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
    if (index.type == IndexType.fullText) {
      return super.compileSchemaIndex(table, index);
    }
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

  @override
  CompiledQuery compileTables({String? schema}) =>
      _sqliteObjects('table', schema);

  @override
  CompiledQuery compileViews({String? schema}) =>
      _sqliteObjects('view', schema);

  CompiledQuery _sqliteObjects(String type, String? schema) => CompiledQuery(
    sql:
        'select name, ? as "schema", sql as definition from ${quoteSchemaIdentifier(schema ?? 'main')}.sqlite_schema '
        "where type = ? and substr(name, 1, 7) <> 'sqlite_' order by name",
    bindings: [schema ?? 'main', type],
  );

  @override
  CompiledQuery compileColumns(String table) {
    final parts = schemaTableParts(table);
    final schema = parts.length == 2 ? parts.first : 'main';
    return CompiledQuery(
      sql:
          'select p.name, lower(case when instr(p.type, \'(\') > 0 '
          'then substr(p.type, 1, instr(p.type, \'(\') - 1) else p.type end) as type_name, p.type as type, '
          'not (p."notnull" or p.pk > 0 and (p.type = \'INTEGER\' or instr(upper(s.sql), \'WITHOUT ROWID\') > 0)) as nullable, '
          'p."notnull" as raw_notnull, s.sql as table_sql, p.dflt_value as default_value, p.pk > 0 and p.type = \'INTEGER\' '
          'and (select count(*) from pragma_table_xinfo(?, ?) where pk > 0) = 1 '
          'and instr(upper(s.sql), \'WITHOUT ROWID\') = 0 as auto_increment, '
          'p.hidden <> 0 as generated, p.pk as primary_position '
          'from pragma_table_xinfo(?, ?) p left join ${quoteSchemaIdentifier(schema)}.sqlite_schema s '
          'on s.type = \'table\' and s.name = ? order by p.cid',
      bindings: [parts.last, schema, parts.last, schema, parts.last],
    );
  }

  @override
  Map<String, Object?> normalizeColumnMetadata(Map<String, Object?> row) {
    final sql = row['table_sql'] as String?;
    if (sql == null ||
        RegExp(
          r'^\s*create\s+virtual\s+table\b',
          caseSensitive: false,
        ).hasMatch(sql)) {
      return row;
    }
    final table = _SqliteDefinition(sql);
    final definition =
        table.definitions
            .where((d) => _SqliteDefinition.columnName(d) == row['name'])
            .single;
    final column = _SqliteColumn(definition);
    final collation = column.constraints.where(
      (c) => _SqliteDefinition.constraintKind(c) == 'collate',
    );
    final generation = column.constraints.where(
      (c) => const [
        'generated',
        'as',
      ].contains(_SqliteDefinition.constraintKind(c)),
    );
    final primary = column.constraints.where(
      (c) => _SqliteDefinition.constraintKind(c) == 'primary',
    );
    final auto =
        row['auto_increment'] == 1 &&
        !primary.any((c) => _SqliteDefinition.hasKeyword(c, 'desc'));
    String? expression;
    if (generation.isNotEmpty) {
      final text = generation.single;
      final tokens = _SqliteDefinition.tokens(text);
      final open = tokens.firstWhere((t) => t.value == '(');
      final close = tokens.firstWhere((t) => t.value == ')' && t.depth == 0);
      expression = text.substring(open.end, close.start);
    }
    return {
      ...row,
      'auto_increment': auto,
      'nullable':
          !(row['raw_notnull'] == 1 ||
              auto ||
              (row['primary_position'] as int) > 0 &&
                  (_SqliteDefinition.hasKeyword(table.suffix, 'strict') ||
                      _SqliteDefinition.hasKeyword(table.suffix, 'without'))),
      'collation':
          collation.isEmpty
              ? null
              : _SqliteDefinition.tokens(collation.single).last.value,
      'generation': expression,
    };
  }

  @override
  CompiledQuery compileIndexes(String table) {
    final parts = schemaTableParts(table);
    final schema = parts.length == 2 ? parts.first : 'main';
    return CompiledQuery(
      sql:
          'select i.name, c.name as column_name, c.seqno as position, '
          'i."unique" as is_unique, i.origin = \'pk\' as is_primary, \'btree\' as type, s.sql as definition '
          'from pragma_index_list(?, ?) i join pragma_index_xinfo(i.name, ?) c '
          'left join ${quoteSchemaIdentifier(schema)}.sqlite_schema s on s.type = \'index\' and s.name = i.name '
          'where c.key = 1 union all select \'primary\', p.name, p.pk, 1, 1, \'btree\', null '
          'from pragma_table_xinfo(?, ?) p where p.pk > 0 and not exists '
          '(select 1 from pragma_index_list(?, ?) where origin = \'pk\') order by name, position',
      bindings: [
        parts.last,
        schema,
        schema,
        parts.last,
        schema,
        parts.last,
        schema,
      ],
    );
  }

  @override
  CompiledQuery compileForeignKeys(String table) {
    final parts = schemaTableParts(table);
    return CompiledQuery(
      sql:
          'select id, null as name, "from" as column_name, seq as position, '
          '? as foreign_schema, "table" as foreign_table, "to" as foreign_column, on_update, on_delete '
          'from pragma_foreign_key_list(?, ?) order by id, seq',
      bindings: [
        parts.length == 2 ? parts.first : 'main',
        parts.last,
        parts.length == 2 ? parts.first : 'main',
      ],
    );
  }

  @override
  CompiledQuery compileSchemaObjects(String table) {
    final parts = schemaTableParts(table);
    return CompiledQuery(
      sql:
          'select type, name, tbl_name, sql from '
          '${quoteSchemaIdentifier(parts.length == 2 ? parts.first : 'main')}.sqlite_schema order by type, name',
      bindings: [],
    );
  }
}
