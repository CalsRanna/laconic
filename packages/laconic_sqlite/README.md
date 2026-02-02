# laconic_sqlite

SQLite driver for the [Laconic](https://pub.dev/packages/laconic) query builder.

## Installation

```yaml
dependencies:
  laconic: ^2.2.0
  laconic_sqlite: ^1.1.0
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

  // Update data
  await laconic.table('users').where('id', id).update({'age': 26});

  // Delete data
  await laconic.table('users').where('id', id).delete();

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

## License

MIT License
