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
  // Example for MySQL
  final mysqlDb = DB(
    host: 'your_mysql_host', // e.g., '127.0.0.1'
    port: 3306,
    database: 'your_database_name',
    username: 'your_username',
    password: 'your_password',
  );

  // Fetch a single row where id = 1
  try {
    var result = await mysqlDb.table('example_table').where('id', 1).first();
    if (result != null) {
      print('Found record: $result');
    } else {
      print('Record not found.');
    }
  } catch (e) {
    print('Error executing query: $e');
  }

  // Example for SQLite
  var sqliteConfig = SqliteConfig('your_database_file.db'); // e.g., 'laconic.db'
  final sqliteDb = Laconic.sqlite(sqliteConfig);

  // Fetch the first record where id = 1 from the 'users' table
  try {
    var user = await sqliteDb.table('users').where('id', 1).first();
    if (user != null) {
      print('Found user: $user');
    } else {
      print('User not found.');
    }
  } catch (e) {
    print('Error executing SQLite query: $e');
  }
}
```

## Additional Information

This library is still a Work In Progress (WIP). The API may have breaking changes in the future. Use this at your own risk if you decide to use it in a production environment.

Please refer to the `example/` directory for more usage examples.
