// ignore_for_file: unused_local_variable

import 'package:laconic/laconic.dart';

void main() async {
  // ============================================================================
  // 1. DATABASE CONNECTION SETUP
  // ============================================================================

  // MySQL configuration
  var mysqlConfig = MysqlConfig(
    database: 'laconic',
    host: '127.0.0.1',
    password: 'root',
    port: 3306,
    username: 'root',
  );

  // Create Laconic instance with query listener for debugging
  var laconic = Laconic.mysql(
    mysqlConfig,
    listen: (query) {
      print('SQL: ${query.sql}');
      print('Bindings: ${query.bindings}');
    },
  );

  // Alternative: SQLite configuration
  // var sqliteConfig = SqliteConfig('laconic.db');
  // var laconic = Laconic.sqlite(sqliteConfig);

  final userTable = 'users';
  final postTable = 'posts';

  // ============================================================================
  // 2. RAW SQL QUERIES
  // ============================================================================

  // Select all users
  var users = await laconic.select('select * from $userTable');
  print('All users: ${users.length}');

  // Select with parameters
  var user = await laconic.select('select * from $userTable where id = ?', [1]);
  print('User 1: ${user.first['name']}');

  // Insert statement
  await laconic.statement(
    'insert into $userTable (name, age, gender) values (?, ?, ?)',
    ['Alice', 28, 'female'],
  );

  // Update statement
  await laconic.statement('update $userTable set name = ? where id = ?', [
    'Bob',
    2,
  ]);

  // Delete statement
  await laconic.statement('delete from $userTable where id = ?', [99]);

  // ============================================================================
  // 3. QUERY BUILDER - BASIC OPERATIONS
  // ============================================================================

  // Get all records
  var allUsers = await laconic.table(userTable).get();
  print('Total users: ${allUsers.length}');

  // Get first record
  var firstUser = await laconic.table(userTable).first();
  print('First user: ${firstUser['name']}');

  // Select specific columns
  var names = await laconic.table(userTable).select(['name', 'age']).get();
  print('Names: ${names.map((u) => u['name']).join(', ')}');

  // Count records
  var count = await laconic.table(userTable).count();
  print('User count: $count');

  // Check if records exist
  var hasUsers =
      await laconic.table(userTable).where('age', 25, comparator: '>').exists();
  print('Has users over 25: $hasUsers');

  // ============================================================================
  // 4. WHERE CLAUSES
  // ============================================================================

  // Basic where
  var youngUsers =
      await laconic.table(userTable).where('age', 25, comparator: '<').get();

  // Multiple where conditions (AND)
  var results =
      await laconic
          .table(userTable)
          .where('age', 25, comparator: '>')
          .where('gender', 'male')
          .get();

  // OR conditions
  var maleOrYoung =
      await laconic
          .table(userTable)
          .where('gender', 'male')
          .orWhere('age', 25, comparator: '<')
          .get();

  // WHERE IN
  var specificUsers =
      await laconic.table(userTable).whereIn('id', [1, 2, 3]).get();

  // WHERE NOT IN
  var excludedUsers =
      await laconic.table(userTable).whereNotIn('id', [1, 2]).get();

  // WHERE NULL
  var usersWithoutEmail =
      await laconic.table(userTable).whereNull('email').get();

  // WHERE NOT NULL
  var usersWithEmail =
      await laconic.table(userTable).whereNotNull('email').get();

  // WHERE BETWEEN
  var ageRange =
      await laconic
          .table(userTable)
          .whereBetween('age', min: 20, max: 30)
          .get();

  // WHERE NOT BETWEEN
  var outsideRange =
      await laconic
          .table(userTable)
          .whereNotBetween('age', min: 20, max: 30)
          .get();

  // WHERE COLUMN (compare two columns)
  var sameNameAndEmail =
      await laconic
          .table(userTable)
          .whereColumn('first_name', 'last_name')
          .get();

  // WHERE ALL (all columns must match)
  var allMatch =
      await laconic
          .table(userTable)
          .whereAll(['name', 'email'], '%john%', operator: 'like')
          .get();

  // WHERE ANY (any column can match)
  var anyMatch =
      await laconic
          .table(userTable)
          .whereAny(['name', 'email', 'phone'], 'john', operator: 'like')
          .get();

  // WHERE NONE (no column should match)
  var noneMatch =
      await laconic
          .table(userTable)
          .whereNone(['name', 'email'], '%spam%', operator: 'like')
          .get();

  // ============================================================================
  // 5. JOINS
  // ============================================================================

  // Basic JOIN
  var userPosts =
      await laconic
          .table('$userTable u')
          .select(['u.name', 'p.title'])
          .join('$postTable p', (join) => join.on('u.id', 'p.user_id'))
          .get();

  // JOIN with multiple conditions
  var complexJoin =
      await laconic
          .table('$userTable u')
          .select(['u.name', 'p.title'])
          .join(
            '$postTable p',
            (join) => join
                .on('u.id', 'p.user_id')
                .orOn('u.email', 'p.author_email')
                .where('p.status', 'published'),
          )
          .get();

  // ============================================================================
  // 6. ORDERING, GROUPING, AND LIMITING
  // ============================================================================

  // Order by
  var sortedUsers =
      await laconic
          .table(userTable)
          .orderBy('name')
          .orderBy('age', direction: 'desc')
          .get();

  // Group by with having
  var userPostCounts =
      await laconic
          .table(postTable)
          .select(['user_id'])
          .groupBy('user_id')
          .having('user_id', 1, operator: '>')
          .get();

  // Distinct
  var uniqueAges =
      await laconic.table(userTable).select(['age']).distinct().get();

  // Limit and offset
  var pagedUsers = await laconic.table(userTable).limit(10).offset(20).get();

  // ============================================================================
  // 7. AGGREGATE FUNCTIONS
  // ============================================================================

  // Average
  var avgAge = await laconic.table(userTable).avg('age');
  print('Average age: $avgAge');

  // Sum
  var totalAge = await laconic.table(userTable).sum('age');
  print('Total age: $totalAge');

  // Max
  var maxAge = await laconic.table(userTable).max('age');
  print('Max age: $maxAge');

  // Min
  var minAge = await laconic.table(userTable).min('age');
  print('Min age: $minAge');

  // Aggregate with conditions
  var avgMaleAge = await laconic
      .table(userTable)
      .where('gender', 'male')
      .avg('age');

  // ============================================================================
  // 8. INSERT OPERATIONS
  // ============================================================================

  // Insert single row
  await laconic.table(userTable).insert([
    {'name': 'John', 'age': 30, 'gender': 'male'},
  ]);

  // Insert multiple rows
  await laconic.table(userTable).insert([
    {'name': 'Jane', 'age': 25, 'gender': 'female'},
    {'name': 'Bob', 'age': 35, 'gender': 'male'},
    {'name': 'Alice', 'age': 28, 'gender': 'female'},
  ]);

  // Insert and get ID
  var newUserId = await laconic.table(userTable).insertGetId({
    'name': 'Charlie',
    'age': 32,
    'gender': 'male',
  });
  print('New user ID: $newUserId');

  // ============================================================================
  // 9. UPDATE OPERATIONS
  // ============================================================================

  // Basic update
  await laconic.table(userTable).where('id', 1).update({
    'name': 'Updated Name',
  });

  // Update multiple records
  await laconic.table(userTable).where('age', 25, comparator: '<').update({
    'status': 'young',
  });

  // Increment
  await laconic.table(userTable).where('id', 1).increment('age');

  // Increment with amount
  await laconic.table(userTable).where('id', 1).increment('age', amount: 5);

  // Increment with extra columns
  await laconic
      .table(userTable)
      .where('id', 1)
      .increment(
        'age',
        extra: {'updated_at': DateTime.now().toIso8601String()},
      );

  // Decrement
  await laconic.table(userTable).where('id', 1).decrement('age');

  // ============================================================================
  // 10. DELETE OPERATIONS
  // ============================================================================

  // Delete with condition
  await laconic.table(userTable).where('id', 99).delete();

  // Delete multiple records
  await laconic.table(userTable).where('status', 'inactive').delete();

  // ============================================================================
  // 11. UTILITY METHODS
  // ============================================================================

  // Pluck - get array of values
  var userNames = await laconic.table(userTable).pluck('name') as List<Object?>;
  print('User names: $userNames');

  // Pluck with key - get map
  var idNameMap =
      await laconic.table(userTable).pluck('name', key: 'id')
          as Map<Object?, Object?>;
  print('ID to name map: $idNameMap');

  // Value - get single value
  var userName = await laconic.table(userTable).where('id', 1).value('name');
  print('User 1 name: $userName');

  // Add select - add columns to existing select
  var extendedSelect =
      await laconic.table(userTable).select(['name']).addSelect([
        'age',
        'gender',
      ]).get();

  // When - conditional query building
  var role = 'admin';
  var conditionalQuery =
      await laconic
          .table(userTable)
          .when(
            role == 'admin',
            (query) => query.where('is_admin', true),
            otherwise: (query) => query.where('is_active', true),
          )
          .get();

  // Sole - ensure exactly one result (throws if zero or multiple)
  try {
    var singleUser =
        await laconic
            .table(userTable)
            .where('email', 'unique@example.com')
            .sole();
    print('Found unique user: ${singleUser['name']}');
  } catch (e) {
    print('Expected single result but got different count');
  }

  // ============================================================================
  // 12. TRANSACTIONS
  // ============================================================================

  try {
    await laconic.transaction(() async {
      // Insert user
      var userId = await laconic.table(userTable).insertGetId({
        'name': 'Transaction User',
        'age': 30,
        'gender': 'male',
      });

      // Insert related post
      await laconic.table(postTable).insert([
        {'user_id': userId, 'title': 'First Post', 'content': 'Content here'},
      ]);

      // If any operation fails, the entire transaction will be rolled back
    });
    print('Transaction completed successfully');
  } catch (e) {
    print('Transaction failed: $e');
  }

  // ============================================================================
  // 13. CLEANUP
  // ============================================================================

  // Always close the connection when done
  await laconic.close();
  print('Connection closed');
}
