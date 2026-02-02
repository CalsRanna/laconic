# laconic_postgresql

PostgreSQL driver for the [Laconic](https://pub.dev/packages/laconic) query builder.

## Installation

```yaml
dependencies:
  laconic: ^2.2.0
  laconic_postgresql: ^1.1.0
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

  // Update data
  await laconic.table('users').where('id', id).update({'age': 26});

  // Delete data
  await laconic.table('users').where('id', id).delete();

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

The PostgreSQL driver uses connection pooling internally for better performance. Connections are managed automatically and released back to the pool after each query.

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

## Parameter Binding

PostgreSQL uses numbered placeholders (`$1`, `$2`, ...) instead of `?`. The driver handles this conversion automatically, so you can use the same query builder API as with other databases.

## License

MIT License
