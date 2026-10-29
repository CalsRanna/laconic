## Unreleased

- Apply `distinct` to aggregate inputs for `sum`, `avg`, `min` and `max`.
- Preserve per-partition selection and offsets when using `groupLimit` with
  cursor pagination or ID-based chunking, including `lazyById` and `eachById`.
- Resolve qualified column names and selected aliases in column readers;
  accept qualified cursor column names in `cursorPaginate`.
- Keep PostgreSQL `DISTINCT ON` keys independent of subsequent projection
  changes and preserve them when cloning a query.
- Fix `count` and existence queries using bound `groupByRaw` expressions.
- Count rows selected by `groupLimit`, honor an additional global `limit`, and
  apply `paginate` / `simplePaginate` offsets to the combined result. Direct
  `offset` calls with `groupLimit` retain their per-partition behavior.
- Fix `cursorPaginate` to group existing OR conditions before applying the
  cursor and filter the complete result of `union` / `unionAll` queries.
- Add `SqlGrammar.compileInlineSubquery` so SELECT subqueries can transform SQL
  and bindings together. Its default delegates to the existing `inlineSubquery`
  implementation and preserves bindings.
- Custom grammars using `implements SqlGrammar` must implement the new method;
  subclasses using `extends SqlGrammar` inherit the default implementation.

## 6.0.0

### Breaking changes and migration

- `sum()`, `max()` and `min()` now return `num?` and preserve integer results.
  `avg()` remains `double?`.
- `insert()` returns `Future<bool>`.
- `where('column', null)` and `where('column', null, comparator: '!=' / '<>')`
  now compile to `IS NULL` / `IS NOT NULL`.
- `SqlGrammar.compileSelect` accepts new optional named parameters:
  `selectBindings`, `groupBindings`, `distinctColumns`, `fromSubquery`,
  `fromAlias` and `indexHints`. Grammars that override it must add them.
- `DatabaseDriver` adds `selectStream`. Drivers using `implements DatabaseDriver`
  must implement it; the default implementation buffers `select`.
- `SqlGrammar` adds `randomOrderExpression`, `numberedPlaceholders`,
  `inlineSubquery`, `compileTruncateAll`, `compileInsertOrIgnoreUsing` and
  `compileUpdateFrom`. They have default implementations.
- `whereIn` / `whereNotIn` and their OR variants accept `Object` (a List or a
  subquery); `whereNot` / `orWhereNot` accept a column or a callback;
  `union` / `unionAll` accept a callback or a `QueryBuilder`.
- Use this release with `laconic_sqlite: ^4.0.0`, `laconic_mysql: ^5.0.0` or
  `laconic_postgresql: ^4.0.0`.

### Query builder features

- Nullable retrieval: `firstOrNull`, `findOrNull`, `firstWhereOrNull`,
  `firstOr`, `findOr`, `firstOrFail`, `findOrFail`, `soleValue`, `existsOr`,
  `doesntExistOr`.
- WHERE / HAVING: `orWhereNone`, negated nested groups, `whereIntegerInRaw`
  family, `whereRowValues`, `whereValueBetween`, `whereNullSafeEquals`,
  `havingBetween` / `havingNull` / `havingNotNull` / `havingNested` and OR
  variants, `whereLike(caseSensitive:)`, `whereMap`.
- Writes: operator validation, `Expression` values in INSERT/UPDATE/increment,
  `updateOrInsert`, `incrementEach`, `decrementEach`, `insertUsing`,
  `insertOrIgnoreUsing`.
- Subqueries: `selectSub`, `fromSub`, `fromRaw`, `joinSub`, `leftJoinSub`,
  `rightJoinSub`, `crossJoinSub`, `joinLateral`, `leftJoinLateral`, subqueries
  in `whereIn`, subquery values in `where`, and `insertUsing`.
- Sorting and pagination: `reorder(column, direction)`, `reorderDesc`,
  `inOrderOf`, `forPageAfterId`, `forPageBeforeId`, `paginate`,
  `simplePaginate`, `cursorPaginate`, `getCountForPagination`, plus
  `LaconicPage`, `LaconicSimplePage` and `LaconicCursorPage`.
- Streaming: `cursor`, `lazy`, `lazyById`, `eachById`, and native
  `selectStream` in all official drivers.
- Debugging: `toRawSql`, `dumpRawSql`, `ddRawSql`, `getLimit`, `getOffset`.
- Dialect features: JSON contains/key/length/overlaps with `->` paths, full
  text search (MySQL/PostgreSQL and SQLite FTS5), MySQL binary comparison,
  `straightJoin` and index hints, PostgreSQL `updateFrom`, `groupLimit`,
  `distinct(columns)` and `count(column)`.
- Query hooks: `Laconic(beforeQuery:, afterQuery:)`.
- `selectRaw` and `groupByRaw` accept bindings; date filters accept comparators.

### Fixes

- SQLite ignores row-lock clauses instead of emitting invalid SQL or throwing.
- `inRandomOrder()` uses `rand()` on MySQL and `random()` elsewhere.
- SQLite `truncate()` resets AUTOINCREMENT when `sqlite_sequence` exists.
- Corrected native-expression examples and the SQLite RIGHT JOIN note.

## 5.0.1

- Republish with a plain semantic version without build metadata.
- Update README installation examples for the coordinated patch release.
- No runtime behavior changes.

## 5.0.0

### Breaking changes and migration

- Add `SqlGrammar.compileUnion`. Custom grammars using `extends SqlGrammar` inherit the default implementation; classes using `implements SqlGrammar` must implement the new method.
- `chunkById` now replaces existing ordering with ascending cursor order and applies an initial offset only to the first batch. The cursor must be unique, non-null and included in the result. Chunk sizes must be positive.
- Ordering, limit and offset on the parent builder apply to the complete UNION; clauses inside a UNION callback apply to that branch.
- Use this release with `laconic_sqlite: ^3.0.0`, `laconic_mysql: ^4.0.0` or `laconic_postgresql: ^3.0.0`.

### Fixes

- Preserve valid OR branches when `whereIn` is empty, including nested conditions and all retrieval methods.
- Group existing OR filters before adding a chunk cursor; apply the cursor to the entire UNION. Capture the cursor and batch size before invoking callbacks that may modify the returned list.
- Compile complete UNION branches for retrieval, aggregates and SQL inspection, retaining projections, bindings and branch pagination.
- Preserve grouping and HAVING in existence checks and EXISTS subqueries; count grouped, distinct and UNION results correctly.

### Performance

- Add `LaconicResult.fromRows` to share column metadata and indexes across driver rows without intermediate maps. Duplicate names retain their first position and last value.
- Keep mutable `columns` and `values` compatible. Requesting a row's mutable `columns` list switches that row to linear lookup so external changes remain visible.
- Limit grouped scalar aggregates to the first result, matching their return contract.

## 4.1.0

### Features

- **`LaconicException` now carries structured `driver` and `code` fields**
  (both optional) so consumers can react to driver-specific error codes
  without parsing the message. `driver` is the backend identifier
  (`mysql`, `postgres`, `sqlite`); `code` is the raw driver error code as a
  string (MySQL server error code, PostgreSQL SQLSTATE, SQLite extended
  result code). Values are opaque to the core and never comparable across
  drivers. Existing single-argument constructions are unaffected.

## 4.0.0

### Breaking Changes

- **`LaconicException` simplified** — removed the `cause` and `stackTrace`
  fields. Driver errors are now embedded in the message via `toString()`, so
  exception output no longer repeats the same message as
  `Caused by: ...`. Drivers also rethrow an existing `LaconicException`
  instead of wrapping it again, eliminating nested
  `LaconicException: LaconicException: ...` messages.

## 3.0.0

### Breaking Changes

- **Affected row counts** — `QueryBuilder.update()`, `delete()`, `increment()`, and `decrement()` now return `Future<int>` with the affected row count instead of `Future<void>`
- **Custom driver API** — `DatabaseDriver` implementations must now implement `affectingStatement(String sql, [List<Object?> params])` and return the affected row count reported by the database

### Features

- Added `Laconic.affectingStatement()` to execute UPDATE/DELETE statements, notify the query listener, and return the affected row count

## 2.3.1

### Bug Fixes

- **`clone()` nested WHERE** — `clone()` now recursively deep-copies nested WHERE conditions (`type: 'nested'`), preventing original and cloned builders from sharing nested condition lists
- **`dump()` double compilation** — `toSql()`, `getBindings()`, and `dump()` now share a single compilation via `_compileForDebug()`, eliminating redundant grammar passes

## 2.3.0

### Features

#### New QueryBuilder Methods (Laravel API Alignment)

- **WHERE Sugar**: `whereNot()`, `orWhereNot()`, `whereLike()`, `orWhereLike()`, `whereNotLike()`, `orWhereNotLike()`
- **Ordering Sugar**: `orderByDesc()`, `latest()`, `oldest()`, `inRandomOrder()`, `reorder()`
- **Limit/Offset Sugar**: `skip()`, `take()`, `forPage()`
- **Conditional**: `unless()` (inverse of `when()`)
- **Retrieval Shortcuts**: `find(id)`, `firstWhere(column, value)`
- **Nested WHERE**: `whereNested(callback)`, `orWhereNested(callback)` — parenthesized sub-condition groups
- **WHERE EXISTS**: `whereExists(callback)`, `orWhereExists(callback)`, `whereNotExists(callback)`, `orWhereNotExists(callback)` — subquery EXISTS clauses
- **Date WHERE**: `whereDate(col, val)`, `whereTime(col, val)`, `whereDay(col, val)`, `whereMonth(col, val)`, `whereYear(col, val)` with `or` variants
- **DDL**: `truncate()` — truncates the table (resets auto-increment)
- **Insert Variants**: `insertOrIgnore(data)` — INSERT OR IGNORE; `upsert(data, uniqueBy: [...], update: [...])` — INSERT ON CONFLICT / ON DUPLICATE KEY UPDATE
- **Row Locks**: `lockForUpdate()` (FOR UPDATE), `sharedLock()` (FOR SHARE / LOCK IN SHARE MODE)
- **UNION**: `union(callback)`, `unionAll(callback)` — UNION / UNION ALL subqueries
- **Table Alias**: `from(table)` — change query table (for subqueries)
- **Debug**: `toSql()`, `getBindings()`, `dump()`, `dd()` — inspect SQL without executing
- **Chunking**: `chunk(count, callback)`, `chunkById(count, callback)`, `each(callback)` — process large result sets in batches
- **Clone**: `clone()` — deep copy builder for reusable query scopes

#### New JoinClause Methods

- `whereLike()`, `orWhereLike()`, `whereNotLike()`, `orWhereNotLike()` — LIKE sugar in JOINs
- `whereExists()`, `orWhereExists()`, `whereNotExists()`, `orWhereNotExists()` — EXISTS subqueries in JOINs

#### New Grammar Methods

- `compileTruncate()` — truncate table (abstract, implemented per driver)
- `compileInsertOrIgnore()` — INSERT OR IGNORE (abstract, implemented per driver)
- `compileUpsert()` — UPSERT (abstract, implemented per driver)
- `compileSelect()` now accepts optional `locks` parameter for FOR UPDATE / FOR SHARE

### Performance

- **Empty `whereIn` Short-Circuit**: when `whereIn('col', [])` guarantees zero results, the query builder skips the database round-trip entirely and returns empty results immediately
- **`count()` with GROUP BY**: now uses a subquery (`SELECT COUNT(*) FROM (SELECT 1 ... GROUP BY ...)`) to count groups server-side, instead of fetching all rows
- **`_aggregate()` Preserves Clauses**: `avg()`, `sum()`, `max()`, `min()` now correctly preserve `_groups`, `_havings`, and `_distinct`

### Bug Fixes

- **`update({})` Validation**: now throws `LaconicException` for empty data maps instead of generating invalid SQL

## 2.2.0

### Features

- **New OR WHERE Methods** - Add 11 new OR variant methods to QueryBuilder for Laravel API consistency
  - `orWhereColumn()` - OR column comparison
  - `orWhereIn()` / `orWhereNotIn()` - OR IN conditions
  - `orWhereNull()` / `orWhereNotNull()` - OR NULL conditions
  - `orWhereBetween()` / `orWhereNotBetween()` - OR BETWEEN conditions
  - `orWhereBetweenColumns()` / `orWhereNotBetweenColumns()` - OR BETWEEN columns
  - `orWhereAll()` / `orWhereAny()` - OR multi-column conditions

- **New JoinClause BETWEEN Methods** - Add 8 new BETWEEN methods to JoinClause
  - `whereBetween()` / `whereNotBetween()` - BETWEEN value conditions
  - `orWhereBetween()` / `orWhereNotBetween()` - OR BETWEEN value conditions
  - `whereBetweenColumns()` / `whereNotBetweenColumns()` - BETWEEN column conditions
  - `orWhereBetweenColumns()` / `orWhereNotBetweenColumns()` - OR BETWEEN column conditions

- **New `orHaving()` Method** - Add OR HAVING support for GROUP BY queries

- **Grammar `compileIncrement()` / `compileDecrement()`** - Add abstract methods to SqlGrammar
  - Enables database-specific placeholder handling (PostgreSQL uses `$N`)
  - QueryBuilder now delegates increment/decrement SQL generation to Grammar

### Bug Fixes

- **Fix PostgreSQL increment/decrement** - Previously used `?` placeholders directly, now correctly uses Grammar for `$N` placeholders

## 2.1.0

### Features

- **New `Expression` and `raw()`** - Embed raw SQL expressions in queries without parameterization
- **New `orderByRaw()`** - Add raw ORDER BY expressions with optional bindings
- **New `groupByRaw()`** - Add raw GROUP BY expressions
- **New `havingRaw()` / `orHavingRaw()`** - Add raw HAVING conditions with optional bindings
- **New `selectRaw()`** - Add raw SELECT expressions
- **New `whereRaw()` / `orWhereRaw()`** - Add raw WHERE conditions with optional bindings
- **New `when()`** - Conditionally apply query constraints
- **New `distinct()`** - Select distinct records
- **New `orWhereColumn()`** - OR column comparison

### Bug Fixes

- **`sole()`** now fetches exactly 2 rows to distinguish "no results" from "multiple results"
- **`insert()`** now validates that data is non-empty

## 2.0.0

### Breaking Changes

- **Query execution methods are now async** - `get()`, `first()`, `insert()`, `update()`, `delete()`, etc. all return `Future`
- **`DatabaseDriver` interface** - All driver methods now return `Future`
- **`SqlGrammar` abstract class** - Grammar methods now return `CompiledQuery` synchronously

### Features

- **PostgreSQL Support** - New `laconic_postgresql` driver package with `$N` positional parameter support and RETURNING clause
- **MySQL Support** - New `laconic_mysql` driver package with prepared statements and connection pooling
- **SQLite Support** - New `laconic_sqlite` driver package using `sqlite3` native library
- **Fluent Query Builder** - 57+ methods covering ~75% of Laravel Query Builder API
- **Parameterized Queries** - Automatic SQL injection prevention via parameter binding
- **Transaction Support** - `laconic.transaction()` with automatic commit/rollback
- **JoinClause** - Complex JOIN conditions with ON, WHERE, and nested conditions
- **Query Listener** - `laconic.listen` callback for query logging

## 1.0.0

Initial release.
