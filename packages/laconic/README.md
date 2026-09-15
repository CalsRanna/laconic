# Laconic

[中文文档](README_ZH.md)

A Laravel-style SQL query builder for Dart, supporting MySQL, SQLite, and PostgreSQL databases.

This is the core package that provides the query builder API and abstract driver interface. You'll also need a driver package for your database:

- [laconic_sqlite](https://pub.dev/packages/laconic_sqlite) - SQLite driver
- [laconic_mysql](https://pub.dev/packages/laconic_mysql) - MySQL driver
- [laconic_postgresql](https://pub.dev/packages/laconic_postgresql) - PostgreSQL driver

## Features

- **Laravel-style API** - Familiar query builder syntax with 80+ methods
- **Fluent Interface** - Chainable methods for elegant query building
- **Parameterized Queries** - Bound values for query parameters; raw SQL and identifiers must be trusted
- **Transaction Support** - Complete transaction management
- **Query Listener** - Built-in debugging and logging
- **Driver Abstraction** - Clean separation between query builder and database implementations

## Installation

The core declares Dart SDK `>=3.7.0 <4.0.0`. Running the whole workspace or
the SQLite example below requires Dart 3.10 or a later 3.x SDK with the currently
resolved `sqlite3 3.3.4` dependency.

```yaml
dependencies:
  laconic: ^5.0.1
  laconic_sqlite: ^3.0.1  # Or your preferred driver
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

An empty `whereIn` compiles to false and an empty `whereNotIn` to true, while
retaining the complete Boolean expression. For example,
`whereIn('id', []).orWhere('id', 1)` can still return the row with ID 1.

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
    .whereColumn('created_at', 'updated_at', comparator: '<')
    .get();

// Nested WHERE groups
final users = await laconic.table('users')
    .where('status', 'active')
    .whereNested((q) => q.where('age', 30).orWhere('role', 'admin'))
    .get();
// SQL: WHERE status = ? AND (age = ? OR role = ?)

// Date WHERE clauses
final todayUsers = await laconic.table('users').whereDate('created_at', DateTime.now()).get();
final janUsers = await laconic.table('users').whereMonth('created_at', 1).get();

// WHERE EXISTS subquery
final usersWithPosts = await laconic.table('users u')
    .whereExists((q) => q.from('posts p').whereColumn('p.user_id', 'u.id'))
    .get();

// Debug query
final sql = laconic.table('users').where('active', true).toSql();
print(sql); // SELECT * FROM users WHERE active = ?
```

### Retrieving Single Records

```dart
// Get by primary key (shorthand)
final user = await laconic.table('users').find(1);

// Get first matching record (shorthand)
final admin = await laconic.table('users').firstWhere('role', 'admin');

// Get first record (throws if none found)
final user = await laconic.table('users').first();

// Get sole record (throws if none or multiple found)
final user = await laconic.table('users').where('email', 'john@example.com').sole();

// Get a single column value (null if none found)
final email = await laconic.table('users').where('name', 'John').value('email');

// Pluck column values
final names = await laconic.table('users').pluck('name');           // List
final map = await laconic.table('users').pluck('name', key: 'id');  // Map<id, name>
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

`exists()` and `doesntExist()` retain GROUP BY and HAVING conditions.
`count()` counts groups for grouped queries, distinct rows for distinct queries,
and rows of the complete UNION. Scalar grouped aggregates (`sum`, `avg`, `min`,
`max`) return the first group; select aggregate expressions with `get()` to read
all groups.

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

// Note: delete(), increment(), and decrement() require a WHERE clause by default
// to prevent accidental mass operations. To explicitly allow without WHERE:
// await laconic.table('users').delete(allowWithoutWhere: true);

// Truncate (remove all rows, reset auto-increment)
await laconic.table('logs').truncate();
```

### Ordering and Limiting

```dart
final users = await laconic.table('users')
    .orderBy('name')
    .orderByDesc('created_at')      // sugar for orderBy(col, direction: 'desc')
    .latest()                        // orderByDesc('created_at')
    .oldest('updated_at')            // orderBy('updated_at')
    .inRandomOrder()                 // RANDOM() ordering
    .skip(10)                        // alias for offset
    .take(5)                         // alias for limit
    .forPage(3, perPage: 15)        // limit(15).offset(30)
    .get();
```

### Row Locking

Row locks require MySQL or PostgreSQL and should be used inside a transaction.
SQLite does not support these row-lock clauses.

```dart
// FOR UPDATE — prevent other transactions from modifying selected rows
final users = await laconic.table('users')
    .where('status', 'pending')
    .lockForUpdate()
    .get();

// FOR SHARE (PostgreSQL) / LOCK IN SHARE MODE (MySQL)
final users = await laconic.table('users')
    .where('id', 5)
    .sharedLock()
    .get();
```

### UNION

`union()` removes duplicate rows; `unionAll()` retains them. Each branch keeps
its selected columns, filters, groups, HAVING and pagination. Ordering, limit
and offset on the parent builder apply to the complete UNION. Use output column
names for that final ordering. Both branches must select compatible columns.
`get()`, `first()`, `sole()`, `value()`, `pluck()`, aggregates, `exists()`,
`toSql()` and `getBindings()` all include the UNION.

```dart
final results = await laconic.table('users').select(['id', 'name'])
    .where('role', 'admin')
    .union((q) => q.from('users').select(['id', 'name']).where('role', 'moderator'))
    .orderBy('id').limit(20).get();
```

### Chunking Large Results

`chunkById` reads in ascending order of a unique, non-null cursor column
(default `id`). It replaces existing ordering, applies an initial offset only
to the first batch, and requires the cursor column in the selected result.
`column` chooses the cursor; `alias` qualifies it with a table alias.
Existing OR filters and UNION branches are included in cursor pagination.
All chunk sizes must be positive. `chunk()` and `each()` use OFFSET pagination;
`chunkById()` advances by the last cursor value.

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
```

### Transactions

Await every query inside the transaction callback. MySQL and PostgreSQL pin
queries to one connection/session per driver instance; calls through another
driver keep that driver's own connection. SQLite queues overlapping transactions
and unrelated queries on its single connection. Nested transactions on the same
driver instance throw `LaconicException`; savepoints are not created automatically.

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

## Results and errors

`LaconicResult` supports `row['column']`, `row.columns`, `row.values` and
`row.toMap()`. Driver results share column metadata and a name-to-index map;
column lookup uses that index until the row's mutable `columns` list is requested.
After that, lookup scans the row's list so edits remain visible. Both `columns`
and `values` remain mutable. Duplicate names keep their first position and last
value. Custom drivers can use `LaconicResult.fromRows(columns, rows)`; it retains
each value list when column names are unique.

Driver failures are reported as `LaconicException`. Besides `message`, the
optional `driver` and `code` fields identify the backend and its error code.
Use the backend together with the code when handling an error; codes may be null.

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
  Future<int> affectingStatement(
    String sql,
    [List<Object?> params = const []],
  ) async {
    // Execute UPDATE/DELETE and return the affected row count
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

## Upgrading to 5.0

- Install the core and driver versions shown above: SQLite/PostgreSQL drivers use the 3.0 series and MySQL uses the 4.0 series.
- Custom grammars extending `SqlGrammar` inherit `compileUnion`; classes implementing `SqlGrammar` must implement the added method.
- `chunkById` uses ascending cursor order and a first-batch offset. Parent UNION ordering and pagination apply to the complete result.
- Official drivers isolate transactions by instance and explicitly reject same-instance nested transactions.

See the [CHANGELOG](CHANGELOG.md) for the full release notes.

## License

MIT License
