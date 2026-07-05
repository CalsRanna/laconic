/// This example demonstrates how to use Laconic with a custom driver.
///
/// For practical usage, you'll want to use one of the official drivers:
/// - laconic_sqlite
/// - laconic_mysql
/// - laconic_postgresql
library;

import 'package:laconic/laconic.dart';

/// A simple in-memory driver for demonstration purposes.
class MockDriver implements DatabaseDriver {
  final List<Map<String, Object?>> _data = [];
  static final _grammar = _MockGrammar();

  @override
  SqlGrammar get grammar => _grammar;

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    // In a real driver, this would execute the SQL query
    print('SELECT: $sql');
    print('Params: $params');
    return _data.map((row) => LaconicResult.fromMap(row)).toList();
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    print('STATEMENT: $sql');
    print('Params: $params');
  }

  @override
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    print('INSERT: $sql');
    print('Params: $params');
    final id = _data.length + 1;
    _data.add({'id': id});
    return id;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    print('BEGIN TRANSACTION');
    try {
      final result = await action();
      print('COMMIT');
      return result;
    } catch (e) {
      print('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    print('Connection closed');
  }
}

class _MockGrammar extends SqlGrammar {
  @override
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
  }) {
    final sql = StringBuffer('SELECT ');
    if (distinct) sql.write('DISTINCT ');
    sql.write(columns.isEmpty ? '*' : columns.join(', '));
    sql.write(' FROM $table');
    return CompiledQuery(sql: sql.toString(), bindings: []);
  }

  @override
  CompiledQuery compileInsert({
    required String table,
    required List<Map<String, Object?>> data,
  }) {
    return CompiledQuery(sql: 'INSERT INTO $table ...', bindings: []);
  }

  @override
  CompiledQuery compileUpdate({
    required String table,
    required Map<String, Object?> data,
    required List<Map<String, dynamic>> wheres,
  }) {
    return CompiledQuery(sql: 'UPDATE $table ...', bindings: []);
  }

  @override
  CompiledQuery compileDelete({
    required String table,
    required List<Map<String, dynamic>> wheres,
  }) {
    return CompiledQuery(sql: 'DELETE FROM $table ...', bindings: []);
  }

  @override
  CompiledQuery compileInsertGetId({
    required String table,
    required Map<String, Object?> data,
    String idColumn = 'id',
  }) {
    return CompiledQuery(
      sql: 'INSERT INTO $table ... RETURNING $idColumn',
      bindings: [],
    );
  }

  @override
  CompiledQuery compileIncrement({
    required String table,
    required String column,
    required int amount,
    Map<String, Object?>? extra,
    required List<Map<String, dynamic>> wheres,
  }) {
    return CompiledQuery(
      sql: 'UPDATE $table SET $column = $column + $amount ...',
      bindings: [],
    );
  }

  @override
  CompiledQuery compileDecrement({
    required String table,
    required String column,
    required int amount,
    Map<String, Object?>? extra,
    required List<Map<String, dynamic>> wheres,
  }) {
    return CompiledQuery(
      sql: 'UPDATE $table SET $column = $column - $amount ...',
      bindings: [],
    );
  }

  @override
  CompiledQuery compileTruncate({required String table}) {
    return CompiledQuery(sql: 'TRUNCATE $table', bindings: []);
  }

  @override
  CompiledQuery compileInsertOrIgnore({
    required String table,
    required List<Map<String, Object?>> data,
  }) {
    return CompiledQuery(sql: 'INSERT OR IGNORE INTO $table ...', bindings: []);
  }

  @override
  CompiledQuery compileUpsert({
    required String table,
    required List<Map<String, Object?>> data,
    required List<String> uniqueBy,
    List<String>? update,
  }) {
    return CompiledQuery(sql: 'UPSERT INTO $table ...', bindings: []);
  }
}

void main() async {
  // Create a Laconic instance with a custom driver
  final laconic = Laconic(
    MockDriver(),
    listen: (query) {
      print('Query executed: ${query.sql}');
    },
  );

  // Basic query
  print('--- Basic Query ---');
  await laconic.table('users').get();

  // Query with conditions
  print('\n--- Query with WHERE ---');
  await laconic.table('users').where('active', true).get();

  // Nested WHERE group
  print('\n--- Nested WHERE ---');
  await laconic.table('users')
      .where('status', 'active')
      .whereNested((q) => q.where('age', 18, comparator: '>=').orWhere('role', 'admin'))
      .get();

  // Debug: toSql() / dump()
  print('\n--- Debug ---');
  laconic.table('users').where('name', 'John').dump();
  print('SQL: ${laconic.table('users').where('age', 18, comparator: '>').toSql()}');

  // WHERE EXISTS
  print('\n--- WHERE EXISTS ---');
  await laconic.table('users u')
      .whereExists((q) => q.from('orders o').whereColumn('o.user_id', 'u.id'))
      .get();

  // Upsert
  print('\n--- Upsert ---');
  await laconic.table('users').upsert(
    [{'email': 'john@example.com', 'name': 'John Updated'}],
    uniqueBy: ['email'],
    update: ['name'],
  );

  // Locking
  print('\n--- Locking ---');
  await laconic.table('users').where('status', 'pending').lockForUpdate().get();

  // Union
  print('\n--- Union ---');
  await laconic.table('users').where('role', 'admin')
      .union((q) => q.from('users').where('role', 'moderator'))
      .get();

  // Insert and get ID
  print('\n--- Insert ---');
  final id = await laconic.table('users').insertGetId({
    'name': 'John',
    'email': 'john@example.com',
  });
  print('Inserted ID: $id');

  // Transaction
  print('\n--- Transaction ---');
  await laconic.transaction(() async {
    await laconic.table('users').insert([
      {'name': 'Jane'},
    ]);
  });

  // Chunking
  print('\n--- Chunking ---');
  await laconic.table('users').chunk(2, (batch) async {
    print('Processing ${batch.length} users...');
  });

  // Clone (reusable query scope)
  print('\n--- Clone ---');
  final activeQuery = laconic.table('users').where('active', true).select(['id', 'name']);
  final count = await activeQuery.clone().count();
  final results = await activeQuery.clone().get();
  print('Active users: $count (fetched ${results.length})');

  // Close connection
  await laconic.close();
}
