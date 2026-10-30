## Unreleased

- Add session-pinned advisory migration locks and native pg_dump/psql baselines.
  Preserve schema-qualified history, support existing empty schemas on import,
  and restore inside one native transaction. Requires matching unreleased core
  and native clients compatible with the PostgreSQL server.

- Add GIN full-text indexes with language selection matching `whereFullText`,
  index renaming/drops, comments, collations, current-time defaults and stored
  generated columns. Virtual columns remain unsupported on the PostgreSQL 15
  baseline. Requires the matching unreleased core schema hooks and enum values;
  coordinate minimum core/driver versions via RELEASE.md.

- Add Blueprint shortcuts, integer/text families, FLOAT, JSONB/ULID, CHECK enums,
  precise/timezone-aware temporal types, INET/MACADDR and PostGIS geometry/geography.
  Reject unsigned, SET, bounded BYTEA and direct CHECK-enum member changes.
  PostGIS installation is application-owned. Existing json() remains JSONB.
  Requires matching unreleased core sources; see SCHEMA.md.

- Implement `change()` and catalog metadata for tables, views, columns, indexes,
  and foreign keys, preserving composite-key order and generated/identity flags.
- Requires the matching unreleased core schema contract; coordinate published
  minimum core/driver versions before release.

- Quote query identifiers and support JSON scalar selectors/path updates. Retain
  joined, ordered, and paginated writes using tableoid/ctid target subqueries
  with correctly numbered bindings.
- **Breaking:** adopt the matching unreleased core query compiler contract and
  chunking semantics. Use `Expression`/`*Raw` for SQL expressions. Existing
  version numbers are retained until a coordinated core/driver release.

- Implement core Schema Builder operations, search-path-aware inspection,
  identity columns, and transactional migration DDL.

- Compare JSON overlap elements as JSONB values so numbers, booleans, nulls,
  objects and nested arrays retain their types. Preserve SQL NULL semantics.
- Search non-null full-text columns even when another searched column is NULL.
- Avoid unused JSON path bindings for empty overlap/non-overlap lists.
- Inherit grouped-count and `groupLimit` pagination fixes from the matching
  unreleased core.
- Preserve reordered and repeated numbered parameters when embedding SELECT
  subqueries, including nested subqueries and adjacent bound expressions.
- Requires the matching unreleased core with `SqlGrammar.compileInlineSubquery`.

## 4.0.0

### Breaking changes and migration

- Requires `laconic: ^6.0.0`.
- Implements the new `DatabaseDriver.selectStream` contract with a native
  PostgreSQL result stream.
- Uses the core 6.0 pagination, subquery and dialect contracts.

### Features

- Native streaming through `cursor()`; chunked streaming via `lazy` /
  `lazyById` / `eachById`.
- JSONB contains/key/length/overlaps with `->` paths.
- Full-text search with plain/phrase/websearch/raw modes and configurable
  language.
- LATERAL joins (`joinLateral`, `leftJoinLateral`).
- `updateFrom` (UPDATE ... FROM) and `groupLimit`.
- Subquery embedding with correct `$N` rebasing in SELECT/FROM/JOIN/WHERE.

## 3.0.1

- Republish with a plain semantic version without build metadata.
- Update the core dependency to `laconic: ^5.0.1`.
- Update README installation examples for the coordinated patch release.
- No runtime behavior changes.

## 3.0.0

### Breaking changes and migration

- Requires `laconic: ^5.0.0` and adopts its UNION, cursor-pagination and custom-grammar contracts.
- Reject nested transactions on the same driver instance with `LaconicException`; separate driver instances keep independent transaction contexts.
- Validate raw SQL binding counts. Native `$N` positions are local to each raw clause; when mixed with `?`, question-mark parameters follow the largest native position. Repeated native positions reuse their binding.

### Fixes

- Rebase parameters when embedding raw clauses, EXISTS subqueries and UNION branches without changing quoted text.
- Preserve strings, quoted identifiers, nested comments, dollar-quoted strings and JSON operators during placeholder conversion; support `??` as an explicit question-mark operator escape.
- Prevent cross-driver transaction routing. Serialize transaction cache access and dispose session statements before the transaction session ends, including rollback paths.

### Performance

- Cache prepared statements per reusable physical connection, with at most 50 per connection. Dispose statements on eviction or execution errors and remove cache metadata when connections close.
- Convert raw SQL placeholders in a single scan.
- Convert row values directly into shared result metadata while retaining mutable values and duplicate-column behavior.

## 2.3.0

### Features

- `LaconicException` from driver errors now fills `driver: 'postgres'` and
  `code` with the SQLSTATE error code (e.g. `23505` for a unique
  violation); non-server errors carry no code.
- `PostgresqlDriver.driverName` constant identifies the driver.

## 2.2.0

### Changed

- Requires `laconic: ^4.0.0` (removes the `LaconicException.cause` /
  `stackTrace` fields)
- Driver errors are embedded in the `LaconicException` message; an existing
  `LaconicException` is rethrown as-is instead of being wrapped again

## 2.0.0

### Breaking Changes

- Requires `laconic: ^3.0.0` and implements the new `DatabaseDriver.affectingStatement()` contract

### Features

- `update()`, `delete()`, `increment()`, and `decrement()` now return the affected row count reported by PostgreSQL

## 1.3.1

### Bug Fixes

- **`whereTime` invalid SQL** — Fixed `CAST()` expression missing closing parenthesis and type specifier; now uses `col::time` syntax
- **`whereDay` / `whereMonth` / `whereYear` invalid SQL** — Fixed `EXTRACT()` expressions missing closing parenthesis
- Refactored `_dateFunction` → `_dateExpression(column)` to return complete SQL expressions

### Performance

- **`_convertPlaceholders` fast-path** — Added `String.contains('?')` check before regex matching, eliminating unnecessary regex evaluation for Grammar-generated `$N` SQL

## 1.3.0

### Features

- **New Grammar Methods**: `compileTruncate()`, `compileInsertOrIgnore()`, `compileUpsert()` — supports new core laconic v2.3.0 features
- **Support for `date` WHERE type**: `whereDate()`, `whereTime()`, `whereDay()`, `whereMonth()`, `whereYear()` — uses PostgreSQL's `DATE()`, `col::time`, and `EXTRACT()` functions
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
