## 3.0.0

### Breaking Changes

- **TLS is enabled by default** — `MysqlConfig.useSsl` now defaults to `true`.
  Set `useSsl: false` only when connecting to a trusted server that does not
  support TLS.
- **Client exceptions are private** — the embedded client's `MySQL*Exception`
  types are no longer exported from `package:laconic_mysql/laconic_mysql.dart`.
  Driver operations continue to report failures through `LaconicException`.
- **Embedded client API is internal** — applications must not import files
  below `package:laconic_mysql/src/client/`. Those implementation types and
  names may change without notice.

### Features

- Added `MysqlConfig.useSsl`, `allowBadCertificates`, `securityContext`,
  `connectTimeout`, and `commandTimeout`.
- Added TLS negotiation with optional custom certificate trust configuration.
- Added support for `caching_sha2_password` authentication.
- Added packet fragmentation and reassembly for large MySQL payloads.
- Added typed prepared-statement parameters for `bool`, `int`, `double`,
  `DateTime`, `Uint8List`, and `BigInt`.
- Added decoding for additional binary result types, including dates, unsigned
  integers, JSON, and binary values.

### Reliability

- Connection pool slots are always released when a query or transaction fails.
- Concurrent pool acquisition now respects `maxConnections` and serves waiters
  in order.
- Prepared statements are cached per connection with LRU eviction and are
  invalidated when their connection is removed.
- Added connection and command timeouts, packet sequence validation, and
  transaction rollback error reporting.

### Internal Changes

- Replaced the external `mysql_client` dependency with an internally maintained
  pure-Dart implementation.
- Reorganized the client into connection, transport, protocol, and result
  layers.
- Replaced `tuple` values with Dart 3 records and removed the `tuple`
  dependency.
- Standardized internal type names on the `Mysql` prefix.

## 2.1.0

### Features

- `update()` now returns the number of rows matched by its `WHERE` clause. Updating an existing row to its current values returns `1`, while a missing row returns `0`.
- The maintained MySQL client implementation is embedded as a private
  implementation detail, so consumers no longer need a separate
  `mysql_client` dependency or override.
- MySQL exception types are exported from `package:laconic_mysql/laconic_mysql.dart` for driver-specific error handling.

## 2.0.0

### Breaking Changes

- Requires `laconic: ^3.0.0` and implements the new `DatabaseDriver.affectingStatement()` contract

### Features

- `update()`, `delete()`, `increment()`, and `decrement()` now return the affected row count reported by MySQL

## 1.3.2

### Bug Fixes

- **Fix connection pool slot leak on query errors** — Replaced use of `mysql_client` 0.0.27's `MySQLConnectionPool.withConnection`, which did not return connections when the callback threw. After about `maxConnections` failed queries the pool could hang forever. Laconic now uses an internal pool that always releases connections in `finally` (including failed transactions and prepared-statement errors).

### Features

- **`MysqlConfig.maxConnections`** — Optional pool size (default `10`, same as before).

## 1.3.1

### Changes

- Refactored `_dateFunction` → `_dateExpression(column)` for consistency with other drivers (no behavioral change)

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
