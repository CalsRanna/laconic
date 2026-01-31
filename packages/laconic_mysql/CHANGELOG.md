## 1.0.0

Initial release of the MySQL driver for Laconic query builder.

### Features

- **`MysqlDriver`** - MySQL database driver implementing `DatabaseDriver` interface
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

final laconic = Laconic(MysqlDriver(MysqlConfig(
  database: 'database',
  password: 'password',
)));

final users = await laconic.table('users').get();

await laconic.close();
```

### Dependencies

- `laconic: ^2.0.0`
- `mysql_client: ^0.0.27`
