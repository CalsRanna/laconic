# Laconic

<p align="right">
  <a href="README.md">English</a> | <a href="README_ZH.md">简体中文</a>
</p>

A Laravel-style SQL query builder for Dart, supporting MySQL, SQLite, and PostgreSQL databases. Provides a fluent, chainable API for elegant database queries.

## Features

- **Laravel-style API** - Familiar query builder syntax with 57 methods covering ~75% of Laravel Query Builder's core functionality
- **Multi-database Support** - Support for MySQL, SQLite, and PostgreSQL via separate driver packages
- **Driver Abstraction** - Clean separation between core query builder and database-specific implementations
- **Complete JOIN Support** - INNER, LEFT, RIGHT, CROSS JOIN with comprehensive condition methods
- **Chainable Methods** - Fluent query building experience
- **Parameterized Queries** - Automatic SQL injection prevention
- **Transaction Support** - Complete transaction management
- **Query Listener** - Built-in debugging and logging

## Packages

| Package | Description | Version |
|---------|-------------|---------|
| [laconic](https://pub.dev/packages/laconic) | Core query builder | 2.2.0 |
| [laconic_sqlite](https://pub.dev/packages/laconic_sqlite) | SQLite driver | 1.1.0 |
| [laconic_mysql](https://pub.dev/packages/laconic_mysql) | MySQL driver | 1.1.0 |
| [laconic_postgresql](https://pub.dev/packages/laconic_postgresql) | PostgreSQL driver | 1.1.0 |

## Installation

Add the core package and the driver you need:

```yaml
dependencies:
  laconic: ^2.2.0
  laconic_sqlite: ^1.1.0    # For SQLite
  # laconic_mysql: ^1.1.0   # For MySQL
  # laconic_postgresql: ^1.1.0  # For PostgreSQL
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

// Delete
await laconic.table('users')
    .where('id', 99)
    .delete();

// Note: delete(), increment(), and decrement() require a WHERE clause by default
// to prevent accidental mass operations. To explicitly allow without WHERE:
// await laconic.table('users').delete(allowWithoutWhere: true);
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
