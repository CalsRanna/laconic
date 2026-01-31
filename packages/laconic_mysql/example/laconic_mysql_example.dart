import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';

void main() async {
  // Create a MySQL connection
  // Make sure MySQL is running and the database exists
  final laconic = Laconic(
    MysqlDriver(MysqlConfig(
      host: '127.0.0.1',
      port: 3306,
      database: 'laconic_example',
      username: 'root',
      password: 'password',
    )),
    listen: (query) {
      print('SQL: ${query.sql}');
      print('Bindings: ${query.bindings}');
      print('---');
    },
  );

  try {
    // Create a users table
    await laconic.statement('''
      CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        email VARCHAR(255),
        age INT,
        active TINYINT DEFAULT 1
      )
    ''');

    // Create a posts table
    await laconic.statement('''
      CREATE TABLE IF NOT EXISTS posts (
        id INT AUTO_INCREMENT PRIMARY KEY,
        user_id INT NOT NULL,
        title VARCHAR(255) NOT NULL,
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
    });

    final finalCount = await laconic.table('users').count();
    print('Final user count: $finalCount\n');

    print('=== Cleanup ===\n');

    // Clean up test data
    await laconic.statement('DROP TABLE IF EXISTS posts');
    await laconic.statement('DROP TABLE IF EXISTS users');
    print('Tables dropped.\n');
  } finally {
    // Always close the connection
    await laconic.close();
    print('Connection closed.');
  }
}
