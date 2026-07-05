## 1.3.0

### Features

- **New Grammar Methods**: `compileTruncate()`, `compileInsertOrIgnore()`, `compileUpsert()` — supports new core laconic v2.3.0 features
- **Support for `date` WHERE type**: `whereDate()`, `whereTime()`, `whereDay()`, `whereMonth()`, `whereYear()` — uses PostgreSQL's `DATE()`, `CAST(col AS time)`, and `EXTRACT()` functions
- **Support for `exists` WHERE type**: `whereExists()` / `whereNotExists()` — EXISTS subqueries in WHERE and JOIN conditions, with automatic `$N` placeholder offset in subqueries
- **Support for `locks`**: `lockForUpdate()` compiles to `FOR UPDATE`; `sharedLock()` compiles to `FOR SHARE`
- **Upsert**: `upsert()` compiles to `INSERT INTO ... ON CONFLICT(...) DO UPDATE SET`
- **Insert Or Ignore**: `insertOrIgnore()` compiles to `INSERT INTO ... ON CONFLICT DO NOTHING`

### Performance

- **Pre-compiled RegExp** — `_positionalParamRE` is now `static final`, avoiding re-compilation on every query
- **Prepared Statement Caching** — Frequently used parameterized queries now reuse cached prepared statements (up to 50), eliminating the Parse → Close round-trip on repeated executions

### Bug Fixes

- **More Robust `_compileRawSql`** — Uses `indexOf` to explicitly locate `?` before replacement, avoiding issues with `?` characters inside raw SQL string literals (edge case)

### Improvements

- **Alignment with laconic v2.3.0**: Compile-time compatibility with new `SqlGrammar` abstract methods and updated `compileSelect` signature

## 1.2.0

### Refactoring

- **Improve Transaction Handling** - Replace individual connection management with `runZoned` for transaction context isolation
- **Simplify Query Execution** - Refactor query execution into dedicated `_executeQuery` methods with protocol-based selection, remove placeholder conversion duplication

## 1.1.0

### Features

- **Implement `compileIncrement()` / `compileDecrement()`** - Grammar methods for increment/decrement SQL generation with `$N` positional placeholders
- **JoinClause BETWEEN Support** - Add `between` and `betweenColumns` type handling in `_compileJoinConditions()`

### Bug Fixes

- **Fix Transaction Isolation** - Store `_transactionSession` to ensure all queries within a transaction use the same session

## 1.0.1

### Improvements

- **Grammar Singleton** - `PostgresqlGrammar` is now a static singleton instance, avoiding unnecessary allocations on each access
- **Enhanced Exception Handling** - All catch blocks now preserve the original exception `cause` and `stackTrace` in `LaconicException`

## 1.0.0

Initial release of the PostgreSQL driver for Laconic query builder.

### Features

- PostgreSQL database driver using `postgres` package with connection pooling (max 10)
- `$N` positional parameter support (extended query protocol)
- `RETURNING` clause for `insertGetId()`
- `_convertPlaceholders()` safety net for `?` → `$N` conversion
- Transaction support using `runZoned` for session isolation
- Lazy connection pool initialization
- SSL support via `PostgresqlConfig.useSsl`
