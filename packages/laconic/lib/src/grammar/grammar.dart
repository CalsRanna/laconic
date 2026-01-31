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
  });

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
}
