## 1.0.0

Initial release of the PostgreSQL driver for Laconic query builder.

### Features

- **`PostgresqlDriver`** - PostgreSQL database driver implementing `DatabaseDriver` interface
  - Connection pooling with configurable max connections (default: 10)
  - Automatic `?` to `$1, $2, ...` parameter placeholder conversion
  - `RETURNING id` clause support for `insertGetId()`
  - SSL connection support
  - Transaction support
  - Proper connection pool cleanup on close

- **`PostgresqlConfig`** - Configuration class for PostgreSQL connections
  - `host` - Database server host (default: `localhost`)
  - `port` - Database server port (default: `5432`)
  - `database` - Database name (required)
  - `username` - Database username (default: `postgres`)
  - `password` - Database password (required)
  - `useSsl` - Use SSL connection (default: `false`)

### Usage

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';

final laconic = Laconic(PostgresqlDriver(PostgresqlConfig(
  database: 'database',
  password: 'password',
)));

final users = await laconic.table('users').get();

await laconic.close();
```

### Dependencies

- `laconic: ^2.0.0`
- `postgres: ^3.5.4`
