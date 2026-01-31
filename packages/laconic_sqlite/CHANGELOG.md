## 1.0.0

Initial release of the SQLite driver for Laconic query builder.

### Features

- **`SqliteDriver`** - SQLite database driver implementing `DatabaseDriver` interface
  - Lazy database connection initialization
  - Parameterized query support with `?` placeholders
  - Transaction support
  - Proper resource cleanup on close

- **`SqliteConfig`** - Configuration class for SQLite connections
  - `path` - Database file path (use `:memory:` for in-memory database)

### Usage

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

final db = Laconic(SqliteDriver(SqliteConfig(path: 'app.db')));

final users = await db.table('users').get();

await db.close();
```

### Dependencies

- `laconic: ^2.0.0`
- `sqlite3: ^2.7.5`
