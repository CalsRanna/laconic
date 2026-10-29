import 'package:laconic/src/exception.dart';
import 'package:laconic/src/grammar/compiled_query.dart';
import 'package:laconic/src/expression.dart';
import 'package:laconic/src/schema/blueprint.dart';

/// Abstract base class for SQL grammar implementations.
///
/// SqlGrammar subclasses are responsible for compiling query components into
/// database-specific SQL strings with parameter bindings.
abstract class SqlGrammar {
  /// Whether ordinary table DDL can share a transaction with migration records.
  ///
  /// Individual migrations must opt out when using non-transactional statements.
  bool get supportsSchemaTransactions => false;

  /// Quotes a schema identifier, or each component of a qualified table name.
  String quoteSchemaIdentifier(String name, {bool qualified = false}) {
    final parts = qualified ? schemaTableParts(name) : [name];
    return parts
        .map((part) {
          if (part.isEmpty || part.contains('\u0000')) {
            throw LaconicException(
              'Schema identifiers must be nonempty and contain no NUL',
            );
          }
          return '"${part.replaceAll('"', '""')}"';
        })
        .join('.');
  }

  /// Splits an unquoted table name into an optional schema and a table.
  List<String> schemaTableParts(String table) {
    final parts = table.split('.');
    if (parts.length > 2 ||
        parts.any((p) => p.isEmpty || p.contains('\u0000'))) {
      throw LaconicException('Expected table or schema.table: $table');
    }
    return parts;
  }

  /// Compiles a literal for a DDL default, which cannot use value bindings.
  ///
  /// [Expression] values are trusted SQL and are emitted unchanged.
  String compileSchemaLiteral(Object? value) {
    if (value == null) return 'null';
    if (value is Expression) return value.sql;
    if (value is bool) return value ? 'true' : 'false';
    if (value is num && value.isFinite) return '$value';
    if (value is DateTime) return compileSchemaLiteral(value.toIso8601String());
    if (value is String && !value.contains('\u0000')) {
      return "'${value.replaceAll("'", "''")}'";
    }
    throw LaconicException('Unsupported schema default: ${value.runtimeType}');
  }

  /// Compiles a portable column type for this database.
  String compileColumnType(ColumnDefinition column) {
    throw LaconicException(
      'This grammar does not implement schema column types',
    );
  }

  /// Compiles the generated-identity clause for an integer column.
  String compileAutoIncrement(ColumnDefinition column) {
    throw LaconicException(
      'This grammar does not support generated identities',
    );
  }

  /// Compiles a column and its inline modifiers.
  String compileColumnDefinition(ColumnDefinition column) {
    if (column.isPrimary && column.isNullable) {
      throw LaconicException('Primary key columns cannot be nullable');
    }
    if (column.autoIncrement &&
        (!column.isPrimary || column.hasDefault || column.isNullable)) {
      throw LaconicException(
        'Generated identities require a non-null primary key without a default',
      );
    }
    final sql = StringBuffer(
      '${quoteSchemaIdentifier(column.name)} ${compileColumnType(column)}',
    );
    if (column.autoIncrement) sql.write(' ${compileAutoIncrement(column)}');
    sql.write(column.isNullable ? ' null' : ' not null');
    if (column.hasDefault) {
      sql.write(' default ${compileSchemaLiteral(column.defaultValue)}');
    }
    if (column.isPrimary) sql.write(' primary key');
    if (column.isUnique) sql.write(' unique');
    return sql.toString();
  }

  /// Compiles an entire table definition before any statement is executed.
  List<CompiledQuery> compileCreateTable(Blueprint blueprint) {
    final table = quoteSchemaIdentifier(blueprint.table, qualified: true);
    final columns = blueprint.commands.whereType<ColumnDefinition>().toList();
    if (columns.isEmpty) {
      throw LaconicException('A table requires at least one column');
    }
    if (columns.map((c) => c.name).toSet().length != columns.length) {
      throw LaconicException('Duplicate columns in table definition');
    }
    final primaryCount =
        columns.where((c) => c.isPrimary).length +
        blueprint.commands
            .whereType<IndexDefinition>()
            .where((i) => i.type == IndexType.primary)
            .length;
    if (primaryCount > 1) {
      throw LaconicException(
        'Use one primary definition for a composite primary key',
      );
    }
    final definitions = columns.map(compileColumnDefinition).toList();
    final indexes = <CompiledQuery>[];
    for (final command in blueprint.commands) {
      if (command is IndexDefinition) {
        if (command.type == IndexType.primary) {
          definitions.add(
            'constraint ${quoteSchemaIdentifier(command.name)} primary key (${compileSchemaColumns(command.columns)})',
          );
        } else {
          indexes.add(compileSchemaIndex(blueprint.table, command));
        }
      } else if (command is ForeignKeyDefinition) {
        definitions.add(compileForeignKey(command));
      } else if (command is SchemaChangeCommand) {
        throw LaconicException(
          'Existing-object alterations cannot be used in create()',
        );
      }
    }
    return [
      CompiledQuery(
        sql: 'create table $table (${definitions.join(', ')})',
        bindings: [],
      ),
      ...indexes,
    ];
  }

  /// Compiles ordered alterations, rejecting unsupported operations eagerly.
  List<CompiledQuery> compileAlterTable(Blueprint blueprint) {
    final table = quoteSchemaIdentifier(blueprint.table, qualified: true);
    final statements = <CompiledQuery>[];
    for (final command in blueprint.commands) {
      if (command is ColumnDefinition) {
        statements.add(compileAddColumn(blueprint.table, command));
      } else if (command is IndexDefinition) {
        if (command.type == IndexType.primary) {
          statements.add(
            CompiledQuery(
              sql:
                  'alter table $table add constraint ${quoteSchemaIdentifier(command.name)} primary key (${compileSchemaColumns(command.columns)})',
              bindings: [],
            ),
          );
        } else {
          statements.add(compileSchemaIndex(blueprint.table, command));
        }
      } else if (command is ForeignKeyDefinition) {
        statements.add(
          CompiledQuery(
            sql: 'alter table $table add ${compileForeignKey(command)}',
            bindings: [],
          ),
        );
      } else if (command is SchemaChangeCommand) {
        statements.add(compileSchemaChange(blueprint.table, command));
      }
    }
    return statements;
  }

  /// Compiles adding a column to an existing table.
  CompiledQuery compileAddColumn(
    String table,
    ColumnDefinition column,
  ) => CompiledQuery(
    sql:
        'alter table ${quoteSchemaIdentifier(table, qualified: true)} add column ${compileColumnDefinition(column)}',
    bindings: [],
  );

  /// Compiles a non-primary index.
  CompiledQuery compileSchemaIndex(
    String table,
    IndexDefinition index,
  ) => CompiledQuery(
    sql:
        'create ${index.type == IndexType.unique ? 'unique ' : ''}index ${quoteSchemaIdentifier(index.name)} on ${quoteSchemaIdentifier(table, qualified: true)} (${compileSchemaColumns(index.columns)})',
    bindings: [],
  );

  /// Compiles a nonempty list of unqualified column identifiers.
  String compileSchemaColumns(List<String> columns) {
    if (columns.isEmpty) {
      throw LaconicException('A key requires at least one column');
    }
    return columns.map(quoteSchemaIdentifier).join(', ');
  }

  /// Compiles a complete named foreign key constraint.
  String compileForeignKey(ForeignKeyDefinition key) {
    if (key.referencedTable == null ||
        key.referencedColumns.length != key.columns.length) {
      throw LaconicException(
        'Foreign keys require a table and matching referenced columns',
      );
    }
    var sql =
        'constraint ${quoteSchemaIdentifier(key.name)} foreign key (${compileSchemaColumns(key.columns)}) references ${quoteSchemaIdentifier(key.referencedTable!, qualified: true)} (${compileSchemaColumns(key.referencedColumns)})';
    if (key.deleteAction != null) {
      sql += ' on delete ${compileReferentialAction(key.deleteAction!)}';
    }
    if (key.updateAction != null) {
      sql += ' on update ${compileReferentialAction(key.updateAction!)}';
    }
    return sql;
  }

  /// Validates and compiles a foreign key action.
  String compileReferentialAction(String action) {
    if (!const [
      'cascade',
      'restrict',
      'no action',
      'set null',
      'set default',
    ].contains(action)) {
      throw LaconicException('Unsupported foreign key action: $action');
    }
    return action;
  }

  /// Compiles dropping or renaming a table member.
  CompiledQuery compileSchemaChange(String table, SchemaChangeCommand command) {
    final target = quoteSchemaIdentifier(table, qualified: true);
    final name = quoteSchemaIdentifier(command.name);
    switch (command.change) {
      case SchemaChange.dropColumn:
        return CompiledQuery(
          sql: 'alter table $target drop column $name',
          bindings: [],
        );
      case SchemaChange.renameColumn:
        return CompiledQuery(
          sql:
              'alter table $target rename column $name to ${quoteSchemaIdentifier(command.newName!)}',
          bindings: [],
        );
      case SchemaChange.dropIndex:
        final parts = schemaTableParts(table);
        final prefix =
            parts.length == 2 ? '${quoteSchemaIdentifier(parts.first)}.' : '';
        return CompiledQuery(sql: 'drop index $prefix$name', bindings: []);
      case SchemaChange.dropForeign:
        return CompiledQuery(
          sql: 'alter table $target drop constraint $name',
          bindings: [],
        );
    }
  }

  /// Compiles dropping a table, optionally tolerating a missing table.
  List<CompiledQuery> compileDropTable(
    String table, {
    bool ifExists = false,
  }) => [
    CompiledQuery(
      sql:
          'drop table ${ifExists ? 'if exists ' : ''}${quoteSchemaIdentifier(table, qualified: true)}',
      bindings: [],
    ),
  ];

  /// Compiles renaming a table within its current schema.
  List<CompiledQuery> compileRenameTable(String from, String to) {
    if (schemaTableParts(to).length != 1) {
      throw LaconicException('The new table name must be unqualified');
    }
    return [
      CompiledQuery(
        sql:
            'alter table ${quoteSchemaIdentifier(from, qualified: true)} rename to ${quoteSchemaIdentifier(to)}',
        bindings: [],
      ),
    ];
  }

  /// Compiles a query returning a row only when the table exists.
  CompiledQuery compileTableExists(String table) {
    throw LaconicException('This grammar does not implement table inspection');
  }

  /// Compiles a query returning ordered column names under the `name` alias.
  CompiledQuery compileColumnListing(String table) {
    throw LaconicException('This grammar does not implement column inspection');
  }

  /// Compiles a SELECT query.
  ///
  /// Parameters:
  /// - [table]: The table name
  /// - [columns]: List of column names to select
  /// - [wheres]: List of WHERE conditions
  /// - [joins]: List of JOIN clauses
  /// - [orders]: List of ORDER BY clauses
  /// - [groups]: List of GROUP BY columns
  /// - [havings]: List of HAVING conditions
  /// - [distinct]: Whether to select distinct records
  /// - [limit]: Optional LIMIT value
  /// - [offset]: Optional OFFSET value
  /// - [selectBindings]: Bindings for raw SELECT expressions, in column order
  /// - [groupBindings]: Bindings for raw GROUP BY expressions, in group order
  /// - [distinctColumns]: Columns for PostgreSQL's `DISTINCT ON`
  /// - [fromSubquery]: A compiled subquery used as the FROM source
  /// - [fromAlias]: The alias for [fromSubquery]; `null` means raw FROM SQL
  ///
  /// [inlineSubquery] converts a compiled subquery into a form that can be
  /// embedded in a larger statement while keeping placeholder order intact.
  CompiledQuery compileSelect({
    required String table,
    required List<String> columns,
    required List<Map<String, dynamic>> wheres,
    required List<Map<String, dynamic>> joins,
    required List<Map<String, dynamic>> orders,
    required List<String> groups,
    required List<Map<String, dynamic>> havings,
    required bool distinct,
    int? limit,
    int? offset,
    List<Map<String, dynamic>> locks = const [],
    List<Object?> selectBindings = const [],
    List<Object?> groupBindings = const [],
    List<String>? distinctColumns,
    CompiledQuery? fromSubquery,
    String? fromAlias,
    List<Map<String, String>> indexHints = const [],
  });

  /// The dialect's random-ordering function used by `inRandomOrder()`.
  String get randomOrderExpression => 'random()';

  /// Compiles an aggregate expression, allowing dialect-specific type handling.
  String compileAggregateExpression(
    String function,
    String column, {
    bool distinct = false,
  }) => '$function(${distinct ? 'DISTINCT ' : ''}$column)';

  /// Whether compiled SQL uses `$1, $2, ...` placeholders.
  bool get numberedPlaceholders => false;

  /// Returns a compiled subquery in a form that can be embedded into a
  /// larger statement.
  ///
  /// Dialects with numbered placeholders override this to normalize them
  /// before the surrounding compiler assigns final indexes.
  String inlineSubquery(CompiledQuery query) => query.sql;

  /// Compiles an inline subquery together with its corresponding bindings.
  ///
  /// The default preserves bindings and delegates SQL conversion to
  /// [inlineSubquery]. Dialects that reorder or repeat placeholders must also
  /// return bindings in their new occurrence order.
  CompiledQuery compileInlineSubquery(CompiledQuery query) =>
      CompiledQuery(sql: inlineSubquery(query), bindings: query.bindings);

  /// Compiles complete SELECT branches with final UNION ordering and pagination.
  ///
  /// [all] contains one flag for each branch after the first. Each branch is
  /// wrapped as a derived table so its own ordering and pagination are preserved.
  CompiledQuery compileUnion({
    required List<CompiledQuery> queries,
    required List<bool> all,
    required List<String> columns,
    required List<Map<String, dynamic>> orders,
    List<Map<String, dynamic>> wheres = const [],
    int? limit,
    int? offset,
    List<Map<String, dynamic>> locks = const [],
  }) {
    final sql = StringBuffer();
    final bindings = <Object?>[];
    for (var i = 0; i < queries.length; i++) {
      if (i > 0) sql.write(all[i - 1] ? ' union all ' : ' union ');
      sql.write('select * from (${queries[i].sql}) as laconic_branch_$i');
      bindings.addAll(queries[i].bindings);
    }
    final outer = compileSelect(
      table: 'laconic_union',
      columns: columns,
      wheres: wheres,
      joins: [],
      orders: orders,
      groups: [],
      havings: [],
      distinct: false,
      limit: limit,
      offset: offset,
      locks: locks,
    );
    return CompiledQuery(
      sql: outer.sql.replaceFirst(
        'from laconic_union',
        'from ($sql) as laconic_union',
      ),
      bindings: [...bindings, ...outer.bindings],
    );
  }

  /// Compiles an INSERT query.
  ///
  /// Parameters:
  /// - [table]: The table name
  /// - [data]: List of maps representing rows to insert
  CompiledQuery compileInsert({
    required String table,
    required List<Map<String, Object?>> data,
  });

  /// Compiles an UPDATE query.
  ///
  /// Parameters:
  /// - [table]: The table name
  /// - [data]: Map of column-value pairs to update
  /// - [wheres]: List of WHERE conditions
  CompiledQuery compileUpdate({
    required String table,
    required Map<String, Object?> data,
    required List<Map<String, dynamic>> wheres,
  });

  /// Compiles a DELETE query.
  ///
  /// Parameters:
  /// - [table]: The table name
  /// - [wheres]: List of WHERE conditions
  CompiledQuery compileDelete({
    required String table,
    required List<Map<String, dynamic>> wheres,
  });

  /// Compiles an INSERT query that returns the inserted ID.
  ///
  /// For PostgreSQL, this adds a RETURNING clause.
  /// For MySQL/SQLite, this is identical to compileInsert() as they
  /// use lastInsertId to get the ID.
  ///
  /// Parameters:
  /// - [table]: The table name
  /// - [data]: Map representing the row to insert
  /// - [idColumn]: The name of the ID column (default: 'id')
  CompiledQuery compileInsertGetId({
    required String table,
    required Map<String, Object?> data,
    String idColumn = 'id',
  });

  /// Compiles an INCREMENT query.
  ///
  /// Parameters:
  /// - [table]: The table name
  /// - [column]: The column to increment
  /// - [amount]: The amount to increment by
  /// - [extra]: Optional additional columns to update
  /// - [wheres]: List of WHERE conditions
  CompiledQuery compileIncrement({
    required String table,
    required String column,
    required int amount,
    Map<String, Object?>? extra,
    required List<Map<String, dynamic>> wheres,
  });

  /// Compiles a DECREMENT query.
  ///
  /// Parameters:
  /// - [table]: The table name
  /// - [column]: The column to decrement
  /// - [amount]: The amount to decrement by
  /// - [extra]: Optional additional columns to update
  /// - [wheres]: List of WHERE conditions
  CompiledQuery compileDecrement({
    required String table,
    required String column,
    required int amount,
    Map<String, Object?>? extra,
    required List<Map<String, dynamic>> wheres,
  });

  /// Compiles an UPDATE ... FROM query.
  ///
  /// Only PostgreSQL implements this; other dialects throw.
  CompiledQuery compileUpdateFrom({
    required String table,
    required String from,
    required Map<String, Object?> data,
    required List<Map<String, dynamic>> wheres,
  }) {
    throw LaconicException('This database engine does not support updateFrom');
  }

  /// Compiles a TRUNCATE query.
  CompiledQuery compileTruncate({required String table});

  /// Compiles every statement required to truncate [table].
  ///
  /// Most dialects need a single statement; SQLite also resets its
  /// `sqlite_sequence` row so AUTOINCREMENT starts over.
  List<CompiledQuery> compileTruncateAll({required String table}) {
    return [compileTruncate(table: table)];
  }

  /// Compiles an INSERT OR IGNORE query.
  CompiledQuery compileInsertOrIgnore({
    required String table,
    required List<Map<String, Object?>> data,
  });

  /// Compiles an INSERT OR IGNORE from a SELECT statement.
  String compileInsertOrIgnoreUsing({
    required String table,
    required List<String> columns,
    required String sql,
  }) {
    return 'insert into $table (${columns.join(', ')}) $sql';
  }

  /// Compiles an UPSERT (INSERT ... ON CONFLICT / ON DUPLICATE KEY UPDATE) query.
  CompiledQuery compileUpsert({
    required String table,
    required List<Map<String, Object?>> data,
    required List<String> uniqueBy,
    List<String>? update,
  });
}
