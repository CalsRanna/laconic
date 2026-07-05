## 1.3.0

### Features

- **New Grammar Methods**: `compileTruncate()`, `compileInsertOrIgnore()`, `compileUpsert()` — supports new core laconic v2.3.0 features
- **Support for `date` WHERE type**: `whereDate()`, `whereTime()`, `whereDay()`, `whereMonth()`, `whereYear()` — uses MySQL's native `DATE()`, `TIME()`, `DAY()`, `MONTH()`, `YEAR()` functions
- **Support for `exists` WHERE type**: `whereExists()` / `whereNotExists()` — EXISTS subqueries in WHERE and JOIN conditions
- **Support for `locks`**: `lockForUpdate()` compiles to `FOR UPDATE`; `sharedLock()` compiles to `LOCK IN SHARE MODE`
- **Upsert**: `upsert()` compiles to `INSERT INTO ... ON DUPLICATE KEY UPDATE`
- **Insert Or Ignore**: `insertOrIgnore()` compiles to `INSERT IGNORE INTO`

### Performance

- **Prepared Statement Caching** — Frequently used parameterized queries now reuse cached prepared statements (up to 50), eliminating the PREPARE → DEALLOCATE round-trip on repeated executions

### Improvements

- **Alignment with laconic v2.3.0**: Compile-time compatibility with new `SqlGrammar` abstract methods and updated `compileSelect` signature

## 1.2.0

### Refactoring

- **Improve Transaction Handling** - Replace individual connection management with `runZoned` for transaction context isolation
- **Simplify Query Execution** - Refactor query execution into dedicated `_executeQuery` methods with protocol-based selection, remove placeholder conversion duplication

## 1.1.0

### Features

- **Implement `compileIncrement()` / `compileDecrement()`** - Grammar methods for increment/decrement SQL generation with `?` placeholders
- **JoinClause BETWEEN Support** - Add `between` and `betweenColumns` type handling in `_compileJoinConditions()`

### Bug Fixes

- **Fix Transaction Isolation** - Use `transactional()` method to ensure all queries within a transaction use the same connection
- **Fix `insertAndGetId()` Method** - Replace prepared statement with direct `execute()` call to fix parameter binding issue

## 1.0.1

### Bug Fixes

- **Fix `insertAndGetId()` Placeholder Conversion** - Now properly uses `_convertPlaceholders()` and `_createNamedParams()` for parameter binding, previously passed raw SQL with `?` placeholders to prepared statements
- **Fix Prepared Statement Leak** - Use `try-finally` to ensure `stmt.deallocate()` is always called even when execution fails
- **Improved Transaction Error Handling** - Rollback failures are now caught and reported alongside the original error instead of silently replacing it

### Improvements

- **Grammar Singleton** - `MysqlGrammar` is now a static singleton instance, avoiding unnecessary allocations on each access

## 1.0.0

Initial release of the MySQL driver for Laconic query builder.

### Features

- MySQL database driver using `mysql_client` package with connection pooling (max 10)
- Prepared statement support (binary protocol) for parameterized queries
- Text protocol fallback for DDL statements (no parameters)
- Transaction support using `runZoned` for connection isolation
- Lazy connection pool initialization
- Auto-increment ID retrieval via `lastInsertId`
