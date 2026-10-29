## Unreleased

- Decode unsigned BIGINT text results above the signed 64-bit range as `BigInt`,
  matching binary query results, including streamed rows.
- Support `offset` without an explicit `limit`.
- Inherit grouped-count and `groupLimit` pagination fixes from the matching
  unreleased core; the current driver/core release mapping remains unchanged.

## 5.0.0

### Breaking changes and migration

- Requires `laconic: ^6.0.0`.
- Implements the new `DatabaseDriver.selectStream` contract with a native
  streaming result set.
- Uses the core 6.0 pagination, subquery and dialect contracts.

### Features

- Native streaming through `cursor()`; chunked streaming via `lazy` /
  `lazyById` / `eachById`.
- JSON contains/key/length/overlaps with `->` paths.
- Full-text search with natural-language/boolean modes and query expansion.
- `whereBinary` and `straightJoin`.
- `useIndex` / `forceIndex` / `ignoreIndex`.
- LATERAL joins (`joinLateral`, `leftJoinLateral`).
- `insertOrIgnoreUsing` and `groupLimit`.

## 4.0.1

- Republish with a plain semantic version without build metadata.
- Update the core dependency to `laconic: ^5.0.1`.
- Update README installation examples for the coordinated patch release.
- No runtime behavior changes.

## 4.0.0

### Breaking changes and migration

- Requires `laconic: ^5.0.0` and adopts its UNION, cursor-pagination and custom-grammar contracts.
- Reject nested transactions on the same driver instance with `LaconicException`. Transactions on different driver instances remain independent.

### Fixes

- Serialize commands on each connection until the complete response is consumed, including streaming results, preventing concurrent commands from exchanging responses.
- Serialize transaction preparation and cache access so concurrent queries reuse the correct statement and connection.
- Isolate transaction contexts by driver instance to prevent calls through a second driver from running against the first driver's database.

### Performance

- Reassemble fragmented packets with linear copying and reuse complete packet views, reducing large-result overhead over TCP and TLS. Preserve packet sequence checks and multi-packet assembly.
- Convert typed row values directly into shared result metadata, preserving mutable results and duplicate-column behavior.

## 3.4.0

### Features

- `LaconicException` from driver errors now fills `driver: 'mysql'` and
  `code` with the MySQL server error code (e.g. `1062` for a duplicate
  entry); client-side and protocol errors carry no code.
- `MysqlDriver.driverName` constant identifies the driver.

## 3.3.0

### Changed

- Requires `laconic: ^4.0.0` (removes the `LaconicException.cause` /
  `stackTrace` fields)
- Driver errors are embedded in the `LaconicException` message; an existing
  `LaconicException` is rethrown as-is instead of being wrapped again

## 3.1.0

### Features

- Added RSA-encrypted `caching_sha2_password` authentication for non-TLS
  connections. Server public-key retrieval is enabled by default when
  `useSsl` is `false`; callers may pin `MysqlConfig.serverPublicKey` and disable
  retrieval with `allowPublicKeyRetrieval: false`.
- Added `MysqlConfig.allowPublicKeyRetrieval` and
  `MysqlConfig.serverPublicKey` for controlling non-TLS authentication.

### Security

- Non-TLS full authentication now encrypts the password with RSA-OAEP instead
  of rejecting the connection. TLS remains enabled by default.
- A pinned server public key takes precedence over public-key retrieval, making
  it possible to authenticate without trusting a key received over the same
  unencrypted connection.

### Tests

- Added protocol-level TLS tests covering SSL negotiation, credential ordering,
  certificate trust, host-name validation, opt-in bad-certificate handling,
  and servers without SSL support.
- Added `caching_sha2_password` tests for retrieved and pinned RSA keys,
  disabled key retrieval, malformed keys, and encryption edge cases.

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
