# Laconic

A Laravel-like SQL query builder for Dart, designed to be flexible, portable, and easy to use. Laconic provides an elegant fluent interface for building and executing database queries across MySQL and SQLite.

## Features

- **Fluent Query Builder API**: Chain methods to build complex queries elegantly
- **Multiple Database Support**: Works with both MySQL and SQLite
- **Transaction Support**: Built-in transaction management for both databases
- **Query Listener**: Debug and log SQL queries with ease
- **Type-Safe**: Leverages Dart's type system for safer query building
- **Laravel-Inspired**: Familiar API for developers coming from Laravel/PHP

## Dependencies

**Important**: This project requires Flutter SDK to be installed on your system before development.

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  laconic: ^1.0.0
```

Then run:

```bash
dart pub get
```

## Quick Start

### MySQL Setup

```dart
import 'package:laconic/laconic.dart';

void main() async {
  var config = MysqlConfig(
    database: 'laconic',
    host: '127.0.0.1',
    password: 'root',
    port: 3306,
    username: 'root',
  );

  var laconic = Laconic.mysql(config);

  // Your queries here
  var users = await laconic.table('users').get();

  await laconic.close();
}
```

### SQLite Setup

```dart
import 'package:laconic/laconic.dart';

void main() async {
  var config = SqliteConfig('laconic.db');
  var laconic = Laconic.sqlite(config);

  // Your queries here
  var users = await laconic.table('users').get();

  await laconic.close();
}
```

## Usage

### Raw SQL Queries

Execute raw SQL queries with parameter binding:

```dart
// Select query
var users = await laconic.select('SELECT * FROM users WHERE id = ?', [1]);

// Insert
await laconic.statement(
  'INSERT INTO users (name, age) VALUES (?, ?)',
  ['John', 25],
);

// Update
await laconic.statement(
  'UPDATE users SET name = ? WHERE id = ?',
  ['Jane', 1],
);

// Delete
await laconic.statement('DELETE FROM users WHERE id = ?', [1]);
```

### Query Builder

#### Basic Queries

```dart
// Select all
var users = await laconic.table('users').get();

// Select with where clause
var user = await laconic.table('users')
    .where('id', 1)
    .first();

// Select specific columns
var users = await laconic.table('users')
    .select(['name', 'email'])
    .get();

// Multiple where conditions (AND)
var users = await laconic.table('users')
    .where('age', 18, comparator: '>')
    .where('status', 'active')
    .get();

// Or where conditions
var users = await laconic.table('users')
    .where('role', 'admin')
    .orWhere('role', 'moderator')
    .get();
```

#### Ordering and Limiting

```dart
// Order by
var users = await laconic.table('users')
    .orderBy('created_at', direction: 'desc')
    .get();

// Limit and offset
var users = await laconic.table('users')
    .limit(10)
    .offset(20)
    .get();
```

#### Joins

```dart
var results = await laconic
    .table('users u')
    .select(['u.name', 'p.title'])
    .join('posts p', (builder) => builder.on('u.id', 'p.user_id'))
    .orderBy('u.name')
    .get();
```

#### Insert

```dart
// Insert single record
await laconic.table('users').insert([
  {'name': 'John', 'age': 25, 'email': 'john@example.com'},
]);

// Insert multiple records
await laconic.table('users').insert([
  {'name': 'John', 'age': 25},
  {'name': 'Jane', 'age': 30},
  {'name': 'Bob', 'age': 35},
]);
```

#### Update

```dart
await laconic.table('users')
    .where('id', 1)
    .update({'name': 'Jane', 'age': 26});
```

#### Delete

```dart
await laconic.table('users')
    .where('id', 1)
    .delete();
```

#### Aggregates

```dart
// Count records
var count = await laconic.table('users').count();

// Get first record (throws if not found)
var user = await laconic.table('users')
    .where('id', 1)
    .first();

// Get single record
var user = await laconic.table('users')
    .where('email', 'user@example.com')
    .sole();
```

### Transactions

```dart
await laconic.transaction(() async {
  await laconic.table('users').insert([
    {'name': 'John', 'balance': 100},
  ]);

  await laconic.table('transactions').insert([
    {'user_id': 1, 'amount': 50},
  ]);

  // If any exception occurs, the transaction will be rolled back
  // Otherwise, it will be committed
});
```

### Query Listener

Debug your queries by listening to all SQL executions:

```dart
var laconic = Laconic.sqlite(
  config,
  listen: (query) {
    print('SQL: ${query.sql}');
    print('Bindings: ${query.bindings}');
  },
);
```

## API Reference

### Laconic Class

Main class for database connections and query execution.

- `Laconic.mysql(MysqlConfig config, {Function(LaconicQuery)? listen})` - Create MySQL connection
- `Laconic.sqlite(SqliteConfig config, {Function(LaconicQuery)? listen})` - Create SQLite connection
- `table(String table)` - Get a query builder for the specified table
- `select(String sql, [List<Object?> params])` - Execute a SELECT query
- `statement(String sql, [List<Object?> params])` - Execute an SQL statement
- `transaction<T>(Future<T> Function() action)` - Execute queries in a transaction
- `close()` - Close the database connection

### QueryBuilder Class

Fluent interface for building queries.

**Query Building:**
- `select(List<String>? columns)` - Specify columns to select
- `where(String column, Object? value, {String comparator = '='})` - Add WHERE condition
- `orWhere(String column, Object? value, {String comparator = '='})` - Add OR WHERE condition
- `join(String targetTable, void Function(JoinBuilder) builder)` - Add JOIN clause
- `orderBy(String column, {String direction = 'asc'})` - Add ORDER BY clause
- `limit(int limit)` - Add LIMIT clause
- `offset(int offset)` - Add OFFSET clause

**Query Execution:**
- `get()` - Execute query and return all results
- `first()` - Get first result (throws if not found)
- `sole()` - Get single result
- `count()` - Count matching records
- `insert(List<Map<String, Object?>> data)` - Insert records
- `update(Map<String, Object?> data)` - Update records
- `delete()` - Delete records

## Testing

Run the test suite:

```bash
# Run all tests
dart test

# Run specific test file
dart test test/laconic_test.dart

# Run specific test by name
dart test --name "select * from users"
```

## Development

```bash
# Install dependencies
dart pub get

# Run static analysis
dart analyze

# Format code
dart format .
```

## Architecture

Laconic uses the Visitor pattern for query building:

1. **Node Layer**: Abstract Syntax Tree (AST) nodes represent query parts
2. **Visitor Layer**: Database-specific visitors convert AST to SQL
3. **Driver Layer**: MySQL and SQLite connections and execution

For detailed architecture documentation, see [CLAUDE.md](CLAUDE.md).

## License

See [LICENSE](LICENSE) file for details.

## Homepage

Visit [https://laconic.antdf.xyz](https://laconic.antdf.xyz) for more information.
