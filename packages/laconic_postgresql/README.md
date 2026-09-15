# laconic_postgresql

[中文文档](README_ZH.md)

PostgreSQL driver for the [Laconic](https://pub.dev/packages/laconic) query builder.

## Installation

The package declares Dart SDK `>=3.7.0 <4.0.0`; the currently resolved
`postgres 3.5.9` requires Dart 3.9 or later. The full workspace also needs
Dart 3.10 for its SQLite dependency.

```yaml
dependencies:
  laconic: ^5.0.1
  laconic_postgresql: ^3.0.1
```

## Usage

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

`PostgresqlConfig` accepts the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `database` | `String` | required | Database name |
| `host` | `String` | `'127.0.0.1'` | PostgreSQL host address |
| `port` | `int` | `5432` | Connection port |
| `username` | `String` | `'postgres'` | Connection username |
| `password` | `String` | required | Connection password |
| `useSsl` | `bool` | `true` | Whether to use SSL connection |

## Connection Pooling

The pool opens lazily and allows up to 10 connections. Queries outside a
transaction borrow and return a connection; transactions hold one for the entire
callback. Prepared statements are cached per reusable physical connection, up to
50 each. Eviction or execution errors dispose statements, and closing a connection
removes its cache metadata. Transactions use a separate session cache that is
disposed before commit or rollback. Call `close()` to shut down the pool.

## Query Listener

You can add a query listener for debugging:

```dart
final laconic = Laconic(
  PostgresqlDriver(PostgresqlConfig(
    database: 'my_database',
    password: 'password',
  )),
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

Transaction queries are pinned to one connection/session and execute serially.
You can await queries with `Future.wait`; each query receives its own result.
Calls through another driver instance use that instance's own connection.

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

## Parameter binding and raw SQL

Raw clauses and driver queries accept `?` or native `$1`, `$2`, … parameters.
Native numbers in each raw clause start locally at `$1`; the grammar rebases them
when composing the complete query. Repeated `$1` references reuse one binding.
If both forms occur in one clause, `?` parameters follow the largest native index.
The binding list must match these positions.

```dart
await laconic.table('users').where('active', true)
    .whereRaw(r'id = $1', [7]).get();
await laconic.select('SELECT ?::jsonb ? ? AS found', ['{"key":1}', 'key']);
```

Question marks inside strings, quoted identifiers, comments and dollar-quoted
strings are preserved. PostgreSQL JSON operators `?`, `?|`, `?&` and `@?` are
preserved; `??` explicitly escapes a bare question-mark operator in raw SQL.

Placeholder conversion uses a single scan, and row values share column metadata
without intermediate map conversion.

## Upgrading from 2.x to 3.0

- Install with `laconic: ^5.0.1` and adopt the core 5.0 UNION and cursor-pagination contracts.
- Raw SQL parameters follow the numbering and count validation above; question marks in quoted strings are retained.
- Same-instance nested transactions fail explicitly; calls through other driver instances retain their own connection and transaction context.
- See the [CHANGELOG](CHANGELOG.md) for the complete release notes.

## License

MIT License
