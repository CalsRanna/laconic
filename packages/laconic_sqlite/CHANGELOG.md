## 1.3.0

### Features

- **New Grammar Methods**: `compileTruncate()`, `compileInsertOrIgnore()`, `compileUpsert()` — supports new core laconic v2.3.0 features
- **Support for `date` WHERE type**: `whereDate()`, `whereTime()`, `whereDay()`, `whereMonth()`, `whereYear()` — uses SQLite's `date()`, `time()`, and `strftime()` functions
- **Support for `exists` WHERE type**: `whereExists()` / `whereNotExists()` — EXISTS subqueries in WHERE and JOIN conditions
- **Support for `locks`**: `lockForUpdate()` compiles to `FOR UPDATE`; `sharedLock()` throws (not supported by SQLite)

### Improvements

- **Alignment with laconic v2.3.0**: Compile-time compatibility with new `SqlGrammar` abstract methods and updated `compileSelect` signature

## 1.2.0

### Bug Fixes

- **sqlite3 v3 Compatibility** - Updated `sqlite3` dependency from `^2.7.5` to `^3.3.2` and replaced deprecated `dispose()` calls with `close()` throughout the driver

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

- SQLite database driver using `sqlite3` native library
- Parameterized queries with `?` placeholders
- Transaction support with BEGIN/COMMIT/ROLLBACK
- Lazy database connection initialization
- Auto-increment ID retrieval via `last_insert_rowid()`
