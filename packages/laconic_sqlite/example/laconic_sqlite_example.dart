import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

void main() async {
  // Create an in-memory SQLite database
  final laconic = Laconic(
    SqliteDriver(SqliteConfig(':memory:')),
    listen: (query) {
      print('SQL: ${query.sql}');
      print('Bindings: ${query.bindings}');
      print('---');
    },
  );

  // Create a users table
  await laconic.statement('''
    CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT,
      age INTEGER,
      active INTEGER DEFAULT 1
    )
  ''');

  // Create a posts table
  await laconic.statement('''
    CREATE TABLE posts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      title TEXT NOT NULL,
      content TEXT,
      FOREIGN KEY (user_id) REFERENCES users(id)
    )
  ''');

  print('=== Insert Data ===\n');

  // Insert users
  final userId1 = await laconic.table('users').insertGetId({
    'name': 'John Doe',
    'email': 'john@example.com',
    'age': 30,
  });
  print('Inserted user with ID: $userId1\n');

  final userId2 = await laconic.table('users').insertGetId({
    'name': 'Jane Smith',
    'email': 'jane@example.com',
    'age': 25,
  });
  print('Inserted user with ID: $userId2\n');

  // Insert posts
  await laconic.table('posts').insert([
    {'user_id': userId1, 'title': 'Hello World', 'content': 'My first post'},
    {'user_id': userId1, 'title': 'Second Post', 'content': 'Another post'},
    {'user_id': userId2, 'title': 'Jane\'s Post', 'content': 'Hello from Jane'},
  ]);

  print('=== Query Data ===\n');

  // Get all users
  final users = await laconic.table('users').get();
  print('All users: ${users.map((u) => u['name']).toList()}\n');

  // Get users with conditions
  final adults = await laconic
      .table('users')
      .where('age', 25, operator: '>=')
      .orderBy('name')
      .get();
  print('Adults: ${adults.map((u) => u['name']).toList()}\n');

  // Count users
  final count = await laconic.table('users').count();
  print('User count: $count\n');

  // Join query
  final postsWithUsers = await laconic
      .table('posts p')
      .select(['p.title', 'u.name as author'])
      .join('users u', (join) => join.on('p.user_id', 'u.id'))
      .get();
  print('Posts with authors:');
  for (final post in postsWithUsers) {
    print('  - ${post['title']} by ${post['author']}');
  }

  print('\n=== Update Data ===\n');

  // Update a user
  await laconic.table('users').where('id', userId1).update({'age': 31});

  // Verify update
  final updated = await laconic.table('users').where('id', userId1).first();
  print('Updated user age: ${updated?['age']}\n');

  print('=== Transaction ===\n');

  // Transaction example
  await laconic.transaction(() async {
    await laconic.table('users').insertGetId({
      'name': 'Transaction User',
      'email': 'tx@example.com',
      'age': 20,
    });
    // If any error occurs here, the transaction will be rolled back
  });

  final finalCount = await laconic.table('users').count();
  print('Final user count: $finalCount\n');

  print('=== Delete Data ===\n');

  // Delete a user
  await laconic.table('users').where('name', 'Transaction User').delete();

  final afterDelete = await laconic.table('users').count();
  print('User count after delete: $afterDelete\n');

  // Close the connection
  await laconic.close();
  print('Connection closed.');
}
