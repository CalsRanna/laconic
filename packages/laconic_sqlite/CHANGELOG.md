## Unreleased

- Support Blueprint `temporary()` with table/index names resolved in the temp
  schema, and temporary-only drops that preserve same-named permanent tables.
  Reject unsupported table options/comments before executing alterations,
  including rebuild and index-rename paths. Requires matching unreleased core
  schema hooks; see SCHEMA.md and RELEASE.md.

- Add migration isolation using a stable SQLite sidecar lock shared across
  connections, isolates and processes. Add native file schema dump/load through
  `sqlite3`; memory and attached-schema dumps explicitly fail. Native baseline
  tests cover structure, history, generated columns and data exclusion.

- Add atomic explicit-index renaming preserving expressions, collation, direction
  and filters, plus named primary-key deletion through table rebuilds.
- Add collations, current-time defaults and virtual/stored generated columns.
  Rebuilds skip generated targets and preserve virtual-column definitions.
- Update the optional schema transaction contract with `disableForeignKeys`:
  index replacement preserves enforcement and supports nested savepoints;
  table rebuilds retain their existing foreign-key restrictions. Requires the
  matching unreleased core; coordinate minimum versions via RELEASE.md.

- Support Blueprint lifecycle/foreign/morph helpers and advanced types using
  SQLite affinities, including CHECK enums, JSONB/ULID and temporal text storage.
  Reject unsigned, SET, spatial and bounded BLOB types, and direct CHECK-enum
  member changes. Requires matching unreleased core sources; see SCHEMA.md.

- Support schema-scoped table wipes for migration CLI `fresh`, including cyclic
  foreign keys and virtual tables. Reuse the atomic schema transaction and restore
  foreign-key settings on success/failure. Use with matching unreleased core sources.

- Rebuild tables atomically for column changes/drops and key alterations, retaining
  data, rowids, autoincrement high-water marks, constraints, generated columns,
  indexes, triggers, and view references. Restore PRAGMA settings on every exit.
- Use savepoints in foreign-keys-off transactions. Reject rebuilds inside an
  existing foreign-keys-on transaction before DDL; use a non-transactional
  migration wrapper for these operations. See SCHEMA.md for rename ordering.
- Add table/view/column/index/foreign-key metadata and native SQL details.
- Requires the matching unreleased core schema contract; coordinate published
  minimum core/driver versions before release.

- Quote query identifiers and support JSON scalar selectors/path updates. Retain
  joined, ordered, and paginated writes using rowid target subqueries (requires
  a rowid table).
- **Breaking:** adopt the matching unreleased core query compiler contract and
  chunking semantics. Use `Expression`/`*Raw` for SQL expressions. Existing
  version numbers are retained until a coordinated core/driver release.

- Implement core Schema Builder operations, column inspection, and transactional
  migration DDL. Reject constraint alterations requiring a table rebuild.

- Restrict FTS5 full-text searches to the requested columns, including queries
  containing OR expressions or explicit column filters.
- Read `selectStream` results through a native cursor instead of buffering all
  rows. Each stream owns its statement and closes it on completion, error or
  cancellation.
- Support `offset` without an explicit `limit`.
- Avoid unused JSON path bindings for empty overlap/non-overlap lists.
- Inherit grouped-count and `groupLimit` pagination fixes from the matching
  unreleased core; the current driver/core release mapping remains unchanged.

## 4.0.0

### Breaking changes and migration

- Requires `laconic: ^6.0.0`.
- Implements the new `DatabaseDriver.selectStream` contract with a native
  SQLite cursor.
- Uses the core 6.0 pagination, subquery and JSON contracts.

### Features

- Native streaming through `cursor()`; chunked streaming via `lazy` /
  `lazyById` / `eachById`.
- JSON contains/key/length/overlaps conditions and `->` path syntax.
- FTS5 full-text search through `whereFullText` (`<table> match ?`).
- `groupLimit` through the core window-function implementation.
- Subquery embedding in SELECT/FROM/JOIN/WHERE and `insertUsing`.

### Fixes

- `truncate()` resets the `sqlite_sequence` row when present.
- Row-lock clauses are ignored rather than emitting invalid SQL.
- `inRandomOrder()` uses `random()`.

## 3.0.1

- Republish with a plain semantic version without build metadata.
- Update the core dependency to `laconic: ^5.0.1`.
- Update README installation examples for the coordinated patch release.
- No runtime behavior changes.

## 3.0.0

### Breaking changes and migration

- Requires `laconic: ^5.0.0` and adopts its UNION, cursor-pagination and custom-grammar contracts.
- Queue overlapping transactions and unrelated queries on the driver's single connection. Reject nested transactions on the same driver instance with `LaconicException`.

### Fixes

- Only roll back transactions successfully opened by the current call, preventing failed or overlapping transactions from rolling back another transaction's writes.
- Keep unrelated writes outside an active transaction and reject queries originating from an expired transaction context.

### Performance

- Convert row values directly into shared result metadata, preserving mutable columns and values and duplicate-column behavior.
- Read the last inserted ID through the native getter without executing a second SQL query.

## 2.3.0

### Features

- `LaconicException` from driver errors now fills `driver: 'sqlite'` and
  `code` with the SQLite extended result code (e.g. `2067` for a UNIQUE
  constraint violation, `1555` for a PRIMARY KEY violation).
- `SqliteDriver.driverName` constant identifies the driver.

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

- `update()`, `delete()`, `increment()`, and `decrement()` now return the affected row count reported by SQLite

## 1.3.1

### Bug Fixes

- **`whereDay` / `whereMonth` / `whereYear` invalid SQL** — Fixed `strftime()` expressions missing closing parenthesis and producing type-mismatched comparisons. Now wraps `strftime()` with `CAST(... AS INTEGER)` for correct type coercion.
- Refactored `_dateFunction` → `_dateExpression(column)` to return complete SQL expressions

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
