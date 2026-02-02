# Laconic

A Laravel-style SQL query builder for Dart, supporting MySQL, SQLite, and PostgreSQL databases.

This is the core package that provides the query builder API and abstract driver interface. You'll also need a driver package for your database:

- [laconic_sqlite](https://pub.dev/packages/laconic_sqlite) - SQLite driver
- [laconic_mysql](https://pub.dev/packages/laconic_mysql) - MySQL driver
- [laconic_postgresql](https://pub.dev/packages/laconic_postgresql) - PostgreSQL driver

## Features

- **Laravel-style API** - Familiar query builder syntax with 57 methods
- **Fluent Interface** - Chainable methods for elegant query building
- **Parameterized Queries** - Automatic SQL injection prevention
- **Transaction Support** - Complete transaction management
- **Query Listener** - Built-in debugging and logging
- **Driver Abstraction** - Clean separation between query builder and database implementations

## Installation

```yaml
dependencies:
  laconic: ^2.2.0
  laconic_sqlite: ^1.1.0  # Or your preferred driver
```

## Quick Start

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

void main() async {
  final laconic = Laconic(SqliteDriver(SqliteConfig('app.db')));

  // Query users
  final users = await laconic.table('users').where('active', true).get();

  // Don't forget to close
  await laconic.close();
}
```

## Query Builder

### Select

```dart
// Get all records
final users = await laconic.table('users').get();

// Get first record
final user = await laconic.table('users').first();

// Select specific columns
final names = await laconic.table('users').select(['name', 'age']).get();

// Distinct
final roles = await laconic.table('users').distinct().select(['role']).get();
```

### WHERE Clauses

```dart
// Basic where
final adults = await laconic.table('users')
    .where('age', 18, comparator: '>=')
    .get();

// Multiple conditions (AND)
final results = await laconic.table('users')
    .where('age', 18, comparator: '>')
    .where('status', 'active')
    .get();

// OR conditions
final users = await laconic.table('users')
    .where('role', 'admin')
    .orWhere('role', 'moderator')
    .get();

// WHERE IN
final users = await laconic.table('users')
    .whereIn('id', [1, 2, 3])
    .get();

// WHERE NULL / NOT NULL
final usersWithEmail = await laconic.table('users')
    .whereNotNull('email')
    .get();

// WHERE BETWEEN
final users = await laconic.table('users')
    .whereBetween('age', min: 18, max: 30)
    .get();

// WHERE column comparison
final users = await laconic.table('users')
    .whereColumn('created_at', 'updated_at', operator: '<')
    .get();
```

### Retrieving Single Records

```dart
// Get first record (throws if none found)
final user = await laconic.table('users').first();

// Get sole record (throws if none or multiple found)
final user = await laconic.table('users').where('email', 'john@example.com').sole();
```

### JOIN Operations

```dart
// INNER JOIN
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// LEFT JOIN with conditions
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .leftJoin(
      'posts p',
      (join) => join
          .on('u.id', 'p.user_id')
          .where('p.status', 'published'),
    )
    .get();

// RIGHT JOIN
final results = await laconic.table('users u')
    .rightJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// CROSS JOIN
final results = await laconic.table('users')
    .crossJoin('roles')
    .get();
```

### Aggregates

```dart
final count = await laconic.table('users').count();
final total = await laconic.table('orders').sum('amount');
final average = await laconic.table('products').avg('price');
final highest = await laconic.table('scores').max('score');
final lowest = await laconic.table('scores').min('score');
```

### Insert / Update / Delete

```dart
// Insert
await laconic.table('users').insert([
  {'name': 'John', 'age': 25},
]);

// Insert and get ID
final id = await laconic.table('users').insertGetId({
  'name': 'Jane',
  'age': 30,
});

// Update
await laconic.table('users')
    .where('id', 1)
    .update({'name': 'New Name'});

// Increment / Decrement
await laconic.table('posts').where('id', 1).increment('views');
await laconic.table('products').where('id', 1).decrement('stock', amount: 5);

// Delete
await laconic.table('users')
    .where('id', 99)
    .delete();

// Note: delete(), increment(), and decrement() require a WHERE clause by default
// to prevent accidental mass operations. To explicitly allow without WHERE:
// await laconic.table('users').delete(allowWithoutWhere: true);
```

### Ordering and Limiting

```dart
final users = await laconic.table('users')
    .orderBy('name')
    .orderByDesc('created_at')
    .limit(10)
    .offset(20)
    .get();
```

### Transactions

```dart
await laconic.transaction(() async {
  final userId = await laconic.table('users').insertGetId({
    'name': 'Test User',
  });

  await laconic.table('posts').insert([
    {'user_id': userId, 'title': 'First Post'},
  ]);
});
```

## Custom Drivers

You can create custom drivers by implementing `DatabaseDriver`:

```dart
class MyDriver implements DatabaseDriver {
  @override
  SqlGrammar get grammar => MyGrammar();

  @override
  Future<List<LaconicResult>> select(String sql, [List<Object?> params = const []]) async {
    // Implementation
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    // Implementation
  }

  @override
  Future<int> insertAndGetId(String sql, [List<Object?> params = const []]) async {
    // Implementation
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    // Implementation
  }

  @override
  Future<void> close() async {
    // Implementation
  }
}
```

## License

MIT License
