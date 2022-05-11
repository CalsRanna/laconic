# laconic

A laravel like sql query builder for mysql designed to be flexible, portable and easy to use.

## Features

This is a dart library inspired by laravel's query builder and has some alike interface to handle database.

## Getting started

```dart
flutter pub add laconic
```

## Usage

```dart
import 'package:laconic/laconic.dart';

void main() async {
  final db = DB(
    host: 'host',
    port: 3306,
    database: 'your database',
    username: 'username',
    password: 'password',
  );
  await db.table('example_table).where('id', 1).sole();
}

```

## Additional information

This library is still [WIP], api may have break changes in the future. Use this at your own risk if you decide to use in your product environment.
