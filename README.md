# laconic

A Laravel-like SQL query builder for MySQL designed to be flexible, portable, and easy to use.

## Features

This is a Dart library inspired by Laravel's query builder, offering a similar interface for database interactions.

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  laconic: ^latest # Replace with the desired version
```

Or install using the command line:

```bash
dart pub add laconic
```

## Usage

```dart
import 'package:laconic/laconic.dart';

void main() async {
  // Mysql and query builder
  var mysqlConfig = MysqlConfig(
    database: 'laconic',
    host: '127.0.0.1',
    password: 'root',
    port: 3306,
    username: 'root',
  );
  var mysqlLaconic = Laconic.mysql(mysqlConfig);
  await mysqlLaconic.table('users').where('id', 1).first();

  // Sqlite and query builder
  var config = SqliteConfig('laconic.db');
  final sqliteLaconic = Laconic.sqlite(config);
  await sqliteLaconic.table('users').where('id', 1).first();
}

```

## Additional Information

This library is still a Work In Progress (WIP). The API may have breaking changes in the future. Use this at your own risk if you decide to use it in a production environment.

Please refer to the `example/` directory for more usage examples.
