# laconic_mysql

MySQL driver for the [Laconic](https://pub.dev/packages/laconic) query builder.

[中文文档](README_ZH.md)

## Installation

```yaml
dependencies:
  laconic: ^3.0.0
  laconic_mysql: ^2.1.0
```

## Usage

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
    // maxConnections: 10, // optional, default 10
  )));

  // Query users
  final users = await laconic.table('users').where('active', true).get();

  // Insert data
  final id = await laconic.table('users').insertGetId({
    'name': 'John',
    'age': 25,
  });

  // Update data and get the matched row count
  final updated =
      await laconic.table('users').where('id', id).update({'age': 26});

  // Delete data and get the affected row count
  final deleted = await laconic.table('users').where('id', id).delete();

  // Don't forget to close
  await laconic.close();
}
```

## Configuration

`MysqlConfig` accepts the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `database` | `String` | required | Database name |
| `host` | `String` | `'127.0.0.1'` | MySQL host address |
| `port` | `int` | `3306` | Connection port |
| `username` | `String` | `'root'` | Connection username |
| `password` | `String` | required | Connection password |
| `maxConnections` | `int` | `10` | Maximum connections in the pool |

## Connection Pooling

The driver maintains a small internal connection pool:

- Connections are created lazily on first use
- Each non-transaction query borrows a connection and **always** returns it, including when SQL errors are thrown
- Transactions pin one connection for the duration of the callback via Zone isolation
- Call `close()` to shut down the pool when the application exits

This avoids connection-slot exhaustion after repeated query failures.

## Update Results

MySQL updates use matched-row semantics. An update whose `WHERE` clause finds
one row returns `1` even when the submitted values are already stored. A
missing row returns `0`. This lets callers distinguish an unchanged existing
record from a record that was concurrently deleted.

The package privately embeds its maintained MySQL client fork. Applications
do not need to depend on or override `mysql_client`.

## Query Listener

You can add a query listener for debugging:

```dart
final laconic = Laconic(
  MysqlDriver(MysqlConfig(
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

## License

MIT License
