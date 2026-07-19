# Laconic

<p align="right">
  <a href="README.md">English</a> | <a href="README_ZH.md">简体中文</a>
</p>

A Laravel-style SQL query builder for Dart, supporting MySQL, SQLite, and PostgreSQL databases. Provides a fluent, chainable API for elegant database queries.

## Features

- **Laravel-style API** - Familiar query builder syntax with 80+ methods covering ~90% of Laravel Query Builder's core functionality
- **Multi-database Support** - MySQL, SQLite, and PostgreSQL via separate driver packages
- **Driver Abstraction** - Clean separation between core query builder and database-specific implementations
- **Complete JOIN Support** - INNER, LEFT, RIGHT, CROSS JOIN with EXISTS subqueries and 30+ condition methods
- **Subqueries** - WHERE EXISTS, UNION, nested WHERE groups
- **Row Locking** - `FOR UPDATE` and `FOR SHARE` support
- **Upsert** - `INSERT ... ON CONFLICT DO UPDATE` across all three databases
- **Date WHERE** - `whereDate`, `whereTime`, `whereDay`, `whereMonth`, `whereYear`
- **Chunking** - Process large result sets in batches with `chunk`, `chunkById`, `each`
- **Debugging** - `toSql()`, `getBindings()`, `dump()`, `dd()` for query inspection
- **Chainable Methods** - Fluent query building experience
- **Parameterized Queries** - Automatic SQL injection prevention
- **Transaction Support** - Complete transaction management
- **Query Listener** - Built-in debugging and logging

## Packages

| Package | Description | Version |
|---------|-------------|---------|
| [laconic](https://pub.dev/packages/laconic) | Core query builder | 3.0.0 |
| [laconic_sqlite](https://pub.dev/packages/laconic_sqlite) | SQLite driver | 2.0.0 |
| [laconic_mysql](https://pub.dev/packages/laconic_mysql) | MySQL driver | 2.0.0 |
| [laconic_postgresql](https://pub.dev/packages/laconic_postgresql) | PostgreSQL driver | 2.0.0 |

## Installation

Add the core package and the driver you need:

```yaml
dependencies:
  laconic: ^3.0.0
  laconic_sqlite: ^2.0.0    # For SQLite
  # laconic_mysql: ^2.0.0   # For MySQL
  # laconic_postgresql: ^2.0.0  # For PostgreSQL
```

Then run:

```bash
dart pub get
```

## Quick Start

### SQLite

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

### MySQL

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';

void main() async {
  final laconic = Laconic(MysqlDriver(MysqlConfig(
    host: '127.0.0.1',
    port: 3306,
    database: 'my_database',
    username: 'root',
    password: 'password',
  )));

  final users = await laconic.table('users').get();
  await laconic.close();
}
```

### PostgreSQL

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';

void main() async {
  final laconic = Laconic(PostgresqlDriver(PostgresqlConfig(
    host: '127.0.0.1',
    port: 5432,
    database: 'my_database',
    username: 'postgres',
    password: 'password',
  )));

  final users = await laconic.table('users').get();
  await laconic.close();
}
```

### Query Listener (for debugging)

```dart
final laconic = Laconic(
  SqliteDriver(SqliteConfig('app.db')),
  listen: (query) {
    print('SQL: ${query.sql}');
    print('Bindings: ${query.bindings}');
  },
);
```

## Basic Usage

### Query Builder

```dart
// Get all records
final users = await laconic.table('users').get();

// Get by primary key (shorthand)
final user = await laconic.table('users').find(1);

// Get first matching record (shorthand)
final admin = await laconic.table('users').firstWhere('role', 'admin');

// Get first record (throws if none found)
final user = await laconic.table('users').first();

// Get sole record (throws if none or multiple found)
final user = await laconic.table('users').where('email', 'john@example.com').sole();

// Select specific columns
final names = await laconic.table('users').select(['name', 'age']).get();

// Count records
final count = await laconic.table('users').count();

// Check if records exist
final exists = await laconic.table('users').where('id', 1).exists();

// Pluck column values
final names = await laconic.table('users').pluck('name');           // List
final map = await laconic.table('users').pluck('name', key: 'id');  // Map<id, name>

// Debug query (prints SQL + bindings, returns this)
laconic.table('users').where('active', true).dump();

// Get SQL without executing
final sql = laconic.table('users').where('age', 18, comparator: '>').toSql();
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

// WHERE IN / NOT IN
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

// LIKE / NOT LIKE (sugar)
final matches = await laconic.table('users')
    .whereLike('name', 'John%')
    .get();

// Nested WHERE groups (parenthesized sub-conditions)
final users = await laconic.table('users')
    .where('status', 'active')
    .whereNested((q) => q.where('age', 30).orWhere('role', 'admin'))
    .get();
// SQL: WHERE status = ? AND (age = ? OR role = ?)

// Date WHERE clauses
final todayUsers = await laconic.table('users').whereDate('created_at', DateTime.now()).get();
final janUsers = await laconic.table('users').whereMonth('created_at', 1).get();
final year2025 = await laconic.table('users').whereYear('created_at', 2025).get();

// WHERE EXISTS subquery
final usersWithPosts = await laconic.table('users u')
    .whereExists((q) => q.from('posts p').whereColumn('p.user_id', 'u.id'))
    .get();

// Conditional WHERE (Laravel's when/unless)
final searchName = 'John';
final users = await laconic.table('users')
    .when(searchName.isNotEmpty, (q) => q.where('name', searchName))
    .get();
```

### JOIN Operations

```dart
// INNER JOIN
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// LEFT JOIN with WHERE + LIKE conditions
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .leftJoin(
      'posts p',
      (join) => join
          .on('u.id', 'p.user_id')
          .where('p.status', 'published')
          .whereLike('p.title', '%Dart%'),
    )
    .get();

// RIGHT JOIN
final results = await laconic.table('users u')
    .rightJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// CROSS JOIN
final results = await laconic.table('users').crossJoin('roles').get();
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

// Insert (ignore duplicates)
await laconic.table('users').insertOrIgnore([
  {'email': 'john@example.com', 'name': 'John'},
]);

// Insert and get ID
final id = await laconic.table('users').insertGetId({
  'name': 'Jane',
  'age': 30,
});

// Upsert (insert or update on conflict)
await laconic.table('users').upsert(
  [{'email': 'john@example.com', 'name': 'John Updated'}],
  uniqueBy: ['email'],
  update: ['name'],
);

// Update (returns the affected row count)
final updated = await laconic.table('users')
    .where('id', 1)
    .update({'name': 'New Name'});

// Increment / Decrement (return the affected row count)
final incremented =
    await laconic.table('posts').where('id', 1).increment('views');
final decremented = await laconic
    .table('products')
    .where('id', 1)
    .decrement('stock', amount: 5);

// Delete (returns the affected row count)
final deleted = await laconic.table('users')
    .where('id', 99)
    .delete();

// Truncate (remove all rows, reset auto-increment)
await laconic.table('logs').truncate();

// Note: delete(), increment(), and decrement() require a WHERE clause by default
// to prevent accidental mass operations.

// Row Locking
final locked = await laconic.table('users')
    .where('status', 'pending')
    .lockForUpdate()   // FOR UPDATE (all DBs)
    .get();

final shared = await laconic.table('users')
    .where('id', 5)
    .sharedLock()      // FOR SHARE (PG) / LOCK IN SHARE MODE (MySQL)
    .get();
```

### Ordering and Limiting

```dart
final users = await laconic.table('users')
    .orderBy('name')
    .orderByDesc('created_at')      // sugar for orderBy(col, direction: 'desc')
    .latest()                        // orderByDesc('created_at')
    .oldest('updated_at')            // orderBy('updated_at')
    .inRandomOrder()                 // RANDOM() ordering
    .skip(10)                        // alias for offset(10)
    .take(5)                         // alias for limit(5)
    .forPage(3, perPage: 15)        // limit(15).offset(30)
    .get();
```

### UNION

```dart
final results = await laconic.table('users')
    .where('role', 'admin')
    .union((q) => q.from('users').where('role', 'moderator'))
    .get();
```

### Chunking Large Results

```dart
// Process 100 records at a time
await laconic.table('users').chunk(100, (users) async {
  for (final user in users) {
    await processUser(user);
  }
});

// ID-based chunking (avoids large OFFSET)
await laconic.table('users').chunkById(100, (users) async {
  // ...
});

// Per-row callback with automatic chunking
await laconic.table('users').each((user) async {
  await sendWelcomeEmail(user['email']);
});

// Clone builder for reusable query scopes
final activeQuery = laconic.table('users').where('active', true);
final count = await activeQuery.clone().count();
final results = await activeQuery.clone().get();
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

## Architecture

### Package Structure

```
laconic/                     # Workspace root
├── packages/
│   ├── laconic/             # Core package
│   │   └── lib/src/
│   │       ├── laconic.dart          # Main entry point
│   │       ├── database_driver.dart  # Abstract driver interface
│   │       ├── grammar/              # SQL grammar (abstract)
│   │       └── query_builder/        # Query builder
│   ├── laconic_sqlite/      # SQLite driver
│   ├── laconic_mysql/       # MySQL driver
│   └── laconic_postgresql/  # PostgreSQL driver
```

### Core Components

1. **Laconic** - Main entry point, delegates to driver
2. **DatabaseDriver** - Abstract interface for database drivers
3. **SqlGrammar** - Abstract base for SQL generation
4. **QueryBuilder** - Fluent query builder

### Custom Drivers

You can create custom drivers by implementing `DatabaseDriver`:

```dart
class MyDriver implements DatabaseDriver {
  @override
  SqlGrammar get grammar => MyGrammar();

  @override
  Future<List<LaconicResult>> select(String sql, [List<Object?> params = const []]) async {
    // Implementation
  }

  // Implement other methods...
}
```

## Testing

```bash
# Run all tests
dart test

# Run specific package tests
dart test packages/laconic/test
dart test packages/laconic_sqlite/test
dart test packages/laconic_mysql/test
dart test packages/laconic_postgresql/test

# Start Docker containers for MySQL/PostgreSQL testing
docker-compose up -d
dart test
docker-compose down
```

## Migration from 1.x

Before (1.x):
```dart
import 'package:laconic/laconic.dart';
final laconic = Laconic.mysql(MysqlConfig(...));
```

After (2.0):
```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
final laconic = Laconic(MysqlDriver(MysqlConfig(...)));
```

## License

MIT License

## Contributing

Issues and Pull Requests are welcome!
