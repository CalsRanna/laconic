## 1.1.0

### Features

- **Implement `compileIncrement()` / `compileDecrement()`** - Grammar methods for increment/decrement SQL generation with `?` placeholders
- **JoinClause BETWEEN Support** - Add `between` and `betweenColumns` type handling in `_compileJoinConditions()`

## 1.0.1

### Bug Fixes

- **Improved Transaction Error Handling** - Rollback failures are now caught and reported alongside the original error instead of silently replacing it

### Improvements

- **Grammar Singleton** - `SqliteGrammar` is now a static singleton instance, avoiding unnecessary allocations on each access
- **Enhanced Exception Handling** - All catch blocks now preserve the original exception `cause` and `stackTrace` in `LaconicException`

## 1.0.0

Initial release of the SQLite driver for Laconic query builder.

### Features

- **`SqliteDriver`** - SQLite database driver implementing `DatabaseDriver` interface
  - Lazy database connection initialization
  - Parameterized query support with `?` placeholders
  - Transaction support
  - Proper resource cleanup on close

- **`SqliteGrammar`** - SQLite-specific SQL grammar extending `SqlGrammar`
  - Standard SQL syntax compilation
  - `?` placeholder parameter binding

- **`SqliteConfig`** - Configuration class for SQLite connections
  - `path` - Database file path (use `:memory:` for in-memory database)

### Usage

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

final laconic = Laconic(SqliteDriver(SqliteConfig('app.db')));

final users = await laconic.table('users').get();

await laconic.close();
```

### Dependencies

- `laconic: ^2.0.0`
- `sqlite3: ^2.7.5`
