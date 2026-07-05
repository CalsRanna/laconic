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
