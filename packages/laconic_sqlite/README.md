# laconic_sqlite

[中文文档](README_ZH.md)

SQLite driver for the [Laconic](https://pub.dev/packages/laconic) query builder.

## Installation

Use Dart 3.10 or a later 3.x SDK with the workspace's currently resolved
`sqlite3 3.3.4` dependency, which raises the package's declared Dart 3.7 minimum.

```yaml
dependencies:
  laconic: ^6.0.0
  laconic_sqlite: ^4.0.0
```

## Usage

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

void main() async {
  // Create a file-based database
  final laconic = Laconic(SqliteDriver(SqliteConfig('app.db')));

  // Or use an in-memory database
  // final laconic = Laconic(SqliteDriver(SqliteConfig(':memory:')));

  // Query users
  final users = await laconic.table('users').where('active', true).get();

  // Insert data
  final id = await laconic.table('users').insertGetId({
    'name': 'John',
    'age': 25,
  });

  // Update data and get the affected row count
  final updated =
      await laconic.table('users').where('id', id).update({'age': 26});

  // Delete data and get the affected row count
  final deleted = await laconic.table('users').where('id', id).delete();

  // Don't forget to close
  await laconic.close();
}
```

## Configuration

`SqliteConfig` accepts a single parameter:

| Parameter | Type | Description |
|-----------|------|-------------|
| `path` | `String` | Path to the SQLite database file. Use `:memory:` for an in-memory database. |

## Query Listener

You can add a query listener for debugging:

```dart
final laconic = Laconic(
  SqliteDriver(SqliteConfig('app.db')),
  listen: (query) {
    print('SQL: ${query.sql}');
    print('Bindings: ${query.bindings}');
  },
);
```

## Transactions

Await every query inside the transaction callback. Nested transactions on the
same driver instance throw `LaconicException`; savepoints are not created
automatically. Different driver instances retain independent transaction contexts.

A transaction owns the driver's single connection until it finishes. Overlapping
transactions and queries outside the transaction wait in a queue. A rollback
affects only writes executed in that transaction. Queries originating from its
context after it finishes are rejected.

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

## Connection lifecycle and performance

The connection opens on first use. Each driver caches up to 50 prepared
statements and releases them on eviction or close. Schema changes executed
through `statement()` invalidate the cache. `insertGetId()` reads the native
last-insert-ID getter, and row conversion builds value lists with shared column
metadata.

The API returns `Future`, but SQLite queries still execute synchronously on the
calling isolate. Applications must schedule long queries on a worker isolate
when needed. SQLite does not support `FOR UPDATE` or `FOR SHARE` row-lock clauses.
Call `close()` to release cached statements and the database connection.

## Upgrading from 3.x to 4.0

- Requires `laconic: ^6.0.0`.
- `selectStream` now uses a native SQLite cursor; `cursor()`, `lazy()` and `lazyById()` are available through the core builder.
- JSON contains/key/length/overlaps and `->` paths are supported.
- `whereFullText` works with FTS5 virtual tables (`<table> match ?`).
- `truncate()` resets the `sqlite_sequence` row when present.
- Same-instance nested transactions fail explicitly; overlapping transactions and unrelated queries wait in a queue instead of joining the current transaction.
- See the [CHANGELOG](CHANGELOG.md) for the complete release notes.

## License

MIT License
