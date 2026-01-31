## 1.0.0

Initial release of the MySQL driver for Laconic query builder.

### Features

- **`MysqlDriver`** - MySQL database driver implementing `LaconicDriver` interface
  - Connection pooling with configurable max connections (default: 10)
  - Automatic `?` to `:p0, :p1, ...` parameter placeholder conversion
  - Transaction support
  - Proper connection pool cleanup on close

- **`MysqlConfig`** - Configuration class for MySQL connections
  - `host` - Database server host (default: `localhost`)
  - `port` - Database server port (default: `3306`)
  - `database` - Database name (required)
  - `username` - Database username (default: `root`)
  - `password` - Database password (required)
  - `secure` - Use secure connection (default: `true`)

### Usage

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';

final db = Laconic(MysqlDriver(MysqlConfig(
  database: 'mydb',
  password: 'secret',
)));

final users = await db.table('users').get();

await db.close();
```

### Dependencies

- `laconic: ^2.0.0`
- `mysql_client: ^0.0.27`
