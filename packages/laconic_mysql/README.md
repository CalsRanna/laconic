# laconic_mysql

MySQL driver for the [Laconic](https://pub.dev/packages/laconic) query builder.

## Installation

```yaml
dependencies:
  laconic: ^2.2.0
  laconic_mysql: ^1.1.0
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

`MysqlConfig` accepts the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `database` | `String` | required | Database name |
| `host` | `String` | `'127.0.0.1'` | MySQL host address |
| `port` | `int` | `3306` | Connection port |
| `username` | `String` | `'root'` | Connection username |
| `password` | `String` | required | Connection password |

## Connection Pooling

The MySQL driver uses connection pooling internally for better performance. Connections are managed automatically and released back to the pool after each query.

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
