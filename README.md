# Laconic

<p align="right">
  <a href="README.md">English</a> | <a href="README_ZH.md">简体中文</a>
</p>

A Laravel-style SQL query builder for Dart, supporting MySQL, SQLite, and PostgreSQL databases. Provides a fluent, chainable API for elegant database queries.

## Features

- **Laravel-style API** - Familiar query builder syntax with 57 methods covering ~75% of Laravel Query Builder's core functionality
- **Multi-database Support** - Support for MySQL, SQLite, and PostgreSQL
- **Complete JOIN Support** - INNER, LEFT, RIGHT, CROSS JOIN with comprehensive condition methods
- **Chainable Methods** - Fluent query building experience
- **Parameterized Queries** - Automatic SQL injection prevention
- **Transaction Support** - Complete transaction management
- **Query Listener** - Built-in debugging and logging

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  laconic: ^1.0.0
```

Then run:

```bash
dart pub get
```

## Quick Start

### Database Connection

#### MySQL

```dart
import 'package:laconic/laconic.dart';

var config = MysqlConfig(
  database: 'my_database',
  host: '127.0.0.1',
  port: 3306,
  username: 'root',
  password: 'password',
);

var laconic = Laconic.mysql(config);
```

#### SQLite

```dart
import 'package:laconic/laconic.dart';

var config = SqliteConfig('database.db');
var laconic = Laconic.sqlite(config);
```

#### PostgreSQL

```dart
import 'package:laconic/laconic.dart';

var config = PostgresqlConfig(
  database: 'my_database',
  host: '127.0.0.1',
  port: 5432,
  username: 'postgres',
  password: 'password',
);

var laconic = Laconic.postgresql(config);
```

### Query Listener (for debugging)

```dart
var laconic = Laconic.mysql(
  config,
  listen: (query) {
    print('SQL: ${query.sql}');
    print('Bindings: ${query.bindings}');
  },
);
```

## Basic Usage

### Raw SQL Queries

```dart
// SELECT query
var users = await laconic.select('SELECT * FROM users WHERE age > ?', [18]);

// INSERT/UPDATE/DELETE statements
await laconic.statement(
  'INSERT INTO users (name, age) VALUES (?, ?)',
  ['John', 25],
);
```

### Query Builder

#### Basic Queries

```dart
// Get all records
var users = await laconic.table('users').get();

// Get first record
var user = await laconic.table('users').first();

// Select specific columns
var names = await laconic.table('users').select(['name', 'age']).get();

// Count records
var count = await laconic.table('users').count();

// Check if records exist
var exists = await laconic.table('users').where('id', 1).exists();
```

#### WHERE Clauses

```dart
// Basic where
var adults = await laconic.table('users')
    .where('age', 18, comparator: '>=')
    .get();

// Multiple conditions (AND)
var results = await laconic.table('users')
    .where('age', 18, comparator: '>')
    .where('status', 'active')
    .get();

// OR conditions
var users = await laconic.table('users')
    .where('role', 'admin')
    .orWhere('role', 'moderator')
    .get();

// WHERE IN
var users = await laconic.table('users')
    .whereIn('id', [1, 2, 3])
    .get();

// WHERE NOT IN
var users = await laconic.table('users')
    .whereNotIn('status', ['banned', 'deleted'])
    .get();

// WHERE NULL / NOT NULL
var usersWithEmail = await laconic.table('users')
    .whereNotNull('email')
    .get();

var usersWithoutEmail = await laconic.table('users')
    .whereNull('email')
    .get();

// WHERE BETWEEN
var users = await laconic.table('users')
    .whereBetween('age', min: 18, max: 30)
    .get();

// WHERE NOT BETWEEN
var users = await laconic.table('users')
    .whereNotBetween('age', min: 18, max: 30)
    .get();

// Column comparison
var users = await laconic.table('users')
    .whereColumn('created_at', 'updated_at', operator: '<')
    .get();

// All columns must match
var users = await laconic.table('users')
    .whereAll(['name', 'email'], '%john%', operator: 'like')
    .get();

// Any column can match
var users = await laconic.table('users')
    .whereAny(['name', 'email', 'phone'], 'john', operator: 'like')
    .get();

// No columns should match
var users = await laconic.table('users')
    .whereNone(['name', 'email'], '%spam%', operator: 'like')
    .get();
```

#### JOIN Operations

```dart
// INNER JOIN
var results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// LEFT JOIN
var results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .leftJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// RIGHT JOIN
var results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .rightJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// CROSS JOIN
var results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .crossJoin('posts p')
    .get();

// Complex JOIN conditions
var results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join(
      'posts p',
      (join) => join
          .on('u.id', 'p.user_id')
          .whereIn('p.status', ['published', 'draft'])
          .whereNotNull('p.content'),
    )
    .get();

// Advanced JOIN conditions
var results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .leftJoin(
      'posts p',
      (join) => join
          .on('u.id', 'p.user_id')
          .orOn('u.email', 'p.author_email')
          .where('p.status', 'published')
          .orWhere('p.featured', true),
    )
    .get();
```

#### Ordering, Grouping, and Pagination

```dart
// Order by
var users = await laconic.table('users')
    .orderBy('name')
    .orderBy('age', direction: 'desc')
    .get();

// Group by
var counts = await laconic.table('posts')
    .select(['user_id'])
    .groupBy('user_id')
    .having('user_id', 1, operator: '>')
    .get();

// Distinct
var ages = await laconic.table('users')
    .select(['age'])
    .distinct()
    .get();

// Pagination
var users = await laconic.table('users')
    .limit(10)
    .offset(20)
    .get();
```

#### Aggregate Functions

```dart
// Average
var avgAge = await laconic.table('users').avg('age');

// Sum
var totalAge = await laconic.table('users').sum('age');

// Max
var maxAge = await laconic.table('users').max('age');

// Min
var minAge = await laconic.table('users').min('age');

// Aggregates with conditions
var avgMaleAge = await laconic.table('users')
    .where('gender', 'male')
    .avg('age');
```

### Insert Operations

```dart
// Insert single record
await laconic.table('users').insert([
  {'name': 'John', 'age': 25, 'gender': 'male'},
]);

// Insert multiple records
await laconic.table('users').insert([
  {'name': 'Jane', 'age': 30, 'gender': 'female'},
  {'name': 'Bob', 'age': 28, 'gender': 'male'},
]);

// Insert and get ID
var id = await laconic.table('users').insertGetId({
  'name': 'Alice',
  'age': 22,
  'gender': 'female',
});
print('New user ID: $id');
```

### Update Operations

```dart
// Basic update
await laconic.table('users')
    .where('id', 1)
    .update({'name': 'New Name'});

// Batch update
await laconic.table('users')
    .where('status', 'pending')
    .update({'status': 'active'});

// Increment
await laconic.table('users')
    .where('id', 1)
    .increment('login_count');

// Increment with amount
await laconic.table('users')
    .where('id', 1)
    .increment('points', amount: 10);

// Increment with extra columns
await laconic.table('users')
    .where('id', 1)
    .increment(
      'age',
      extra: {'updated_at': DateTime.now().toIso8601String()},
    );

// Decrement
await laconic.table('users')
    .where('id', 1)
    .decrement('balance', amount: 100);
```

### Delete Operations

```dart
// Delete with condition
await laconic.table('users')
    .where('id', 99)
    .delete();

// Batch delete
await laconic.table('users')
    .where('status', 'inactive')
    .delete();
```

### Utility Methods

```dart
// pluck - Get array of column values
var names = await laconic.table('users').pluck('name') as List<Object?>;

// pluck - Get key-value map
var idNameMap = await laconic.table('users').pluck('name', key: 'id')
    as Map<Object?, Object?>;

// value - Get single value
var name = await laconic.table('users')
    .where('id', 1)
    .value('name');

// addSelect - Add columns to existing select
var users = await laconic.table('users')
    .select(['name'])
    .addSelect(['age', 'email'])
    .get();

// when - Conditional query building
var role = 'admin';
var users = await laconic.table('users')
    .when(
      role == 'admin',
      (query) => query.where('is_admin', true),
      otherwise: (query) => query.where('is_active', true),
    )
    .get();

// sole - Ensure exactly one result
try {
  var user = await laconic.table('users')
      .where('email', 'unique@example.com')
      .sole();
} catch (e) {
  print('Result not unique or does not exist');
}
```

### Transactions

```dart
try {
  await laconic.transaction(() async {
    // Insert user
    var userId = await laconic.table('users').insertGetId({
      'name': 'Test User',
      'age': 30,
    });

    // Insert related data
    await laconic.table('posts').insert([
      {'user_id': userId, 'title': 'First Post'},
    ]);

    // If any operation fails, the entire transaction will be rolled back
  });
  print('Transaction successful');
} catch (e) {
  print('Transaction failed: $e');
}
```

### Close Connection

```dart
// Always close the connection when done
await laconic.close();
```

## Architecture Overview

### Core Components

1. **Laconic** - Main entry point, manages database connections
2. **QueryBuilder** - Fluent query builder
3. **Grammar** - SQL generation core
   - SqlGrammar: MySQL/SQLite implementation (uses `?` placeholders)
   - PostgresqlGrammar: PostgreSQL implementation (uses `$1, $2, ...` placeholders)
4. **JoinClause** - JOIN condition builder

### Design Patterns

- **Grammar Pattern**: QueryBuilder collects query components, Grammar compiles them into concrete SQL
- **Parameter Binding**: All queries use parameterized bindings to prevent SQL injection
- **Lazy Connection**: Database connections are established on first use

## Dependencies

- `mysql_client: ^0.0.27` - MySQL connectivity
- `sqlite3: ^2.7.5` - SQLite support
- `postgres: ^3.5.5` - PostgreSQL support

## Testing

```bash
# Run all tests
dart test

# Run database-specific tests
dart test test/sqlite_test.dart
dart test test/mysql_test.dart
dart test test/postgresql_test.dart

# Start Docker containers for MySQL/PostgreSQL testing
docker-compose up -d
dart test
docker-compose down
```

## License

MIT License

## Contributing

Issues and Pull Requests are welcome!
