import 'package:laconic/src/grammar/compiled_query.dart';

/// Abstract base class for SQL grammar implementations.
///
/// SqlGrammar subclasses are responsible for compiling query components into
/// database-specific SQL strings with parameter bindings.
abstract class SqlGrammar {
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

  /// Whether compiled SQL uses `$1, $2, ...` placeholders.
  bool get numberedPlaceholders => false;

  /// Returns a compiled subquery in a form that can be embedded into a
  /// larger statement.
  ///
  /// Dialects with numbered placeholders override this to normalize them
  /// before the surrounding compiler assigns final indexes.
  String inlineSubquery(CompiledQuery query) => query.sql;

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
