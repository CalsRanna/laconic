# Laconic

<p align="right">
  <a href="README.md">English</a> | <a href="README_ZH.md">简体中文</a>
</p>

A Laravel-style SQL query builder for Dart, supporting MySQL, MariaDB, SQLite, PostgreSQL, and SQL Server databases. Provides a fluent, chainable API for elegant database queries.

## Features

- **Laravel-style API** - 130+ chainable methods for filtering, joins, aggregates, subqueries, pagination and writes
- **Multi-database Support** - MySQL, MariaDB, SQLite, PostgreSQL, and SQL Server via separate driver packages
- **Subqueries** - SELECT/FROM/JOIN subqueries, WHERE EXISTS, IN subqueries, insert-using and UNION
- **Pagination and Streaming** - `paginate`, `simplePaginate`, `cursorPaginate`, native `cursor()`, `lazy()`, `lazyById()`
- **JSON and Full Text** - JSON contains/key/length/overlaps with `->` paths; MySQL/PostgreSQL full text; SQLite FTS5
- **Dialect Features** - MySQL binary comparisons/index hints/straight joins, PostgreSQL `updateFrom`/LATERAL, `groupLimit`
- **Complete JOIN Support** - INNER, LEFT, RIGHT, CROSS, subquery joins, LATERAL joins and 30+ condition methods
- **Row Locking** - `FOR UPDATE` / shared locks plus portable raw lock clauses
- **Upsert and Bulk Writes** - `insertGetId`, `upsert`, `insertUsing`, `insertOrIgnoreUsing`, `updateOrInsert`, `incrementEach`
- **Date WHERE** - `whereDate`, `whereTime`, `whereDay`, `whereMonth`, `whereYear` with comparators
- **Chunking** - `chunk`, `chunkById`, `each`, `cursor`, `lazy`, `lazyById`, `eachById`
- **Debugging** - `toSql()`, `getBindings()`, `toRawSql()`, `dump()`, `dd()` and query hooks
- **Parameterized Queries** - Bound values for query parameters; raw SQL and identifiers must be trusted
- **Transaction Support** - Complete transaction management
- **Query Listener** - Built-in debugging and logging

## Packages

| Package | Description | Version |
|---------|-------------|---------|
| [laconic](https://pub.dev/packages/laconic) | Core query builder | 6.0.0 |
| [laconic_sqlite](https://pub.dev/packages/laconic_sqlite) | SQLite driver | 4.0.0 |
| [laconic_mysql](https://pub.dev/packages/laconic_mysql) | MySQL driver | 5.0.0 |
| [laconic_postgresql](https://pub.dev/packages/laconic_postgresql) | PostgreSQL driver | 4.0.0 |
| [laconic_mariadb](packages/laconic_mariadb/README.md) | MariaDB 10.11+ | 1.0.0 (unreleased) |
| [laconic_sqlserver](packages/laconic_sqlserver/README.md) | SQL Server 2022+ | 1.0.0 (unreleased) |

MariaDB and SQL Server drivers are currently available in this workspace and are not yet published on pub.dev. See their package READMEs for setup and dialect limitations.

## Installation

The core declares Dart SDK `>=3.7.0 <4.0.0`. Running the whole workspace or
the SQLite example below requires Dart 3.10 or a later 3.x SDK with the currently
resolved `sqlite3 3.3.4` dependency.

Add the core package and the driver you need:

```yaml
dependencies:
  laconic: ^6.0.0
  laconic_sqlite: ^4.0.0    # For SQLite
  # laconic_mysql: ^5.0.0   # For MySQL
  # laconic_postgresql: ^4.0.0  # For PostgreSQL
```

Then run:

```bash
dart pub get
```

## Quick Start

### SQLite

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

void main() async {
  final laconic = Laconic(SqliteDriver(SqliteConfig('app.db')));

  // Query users
  final users = await laconic.table('users').where('active', true).get();

  // Don't forget to close
  await laconic.close();
}
```

### MySQL

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';

void main() async {
  final laconic = Laconic(MysqlDriver(MysqlConfig(
    host: '127.0.0.1',
    port: 3306,
    database: 'my_database',
    username: 'root',
    password: 'password',
  )));

  final users = await laconic.table('users').get();
  await laconic.close();
}
```

### PostgreSQL

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';

void main() async {
  final laconic = Laconic(PostgresqlDriver(PostgresqlConfig(
    host: '127.0.0.1',
    port: 5432,
    database: 'my_database',
    username: 'postgres',
    password: 'password',
  )));

  final users = await laconic.table('users').get();
  await laconic.close();
}
```

### Query Listener (for debugging)

```dart
final laconic = Laconic(
  SqliteDriver(SqliteConfig('app.db')),
  listen: (query) {
    print('SQL: ${query.sql}');
    print('Bindings: ${query.bindings}');
  },
);
```

## Basic Usage

### Query Builder

```dart
// Get all records
final users = await laconic.table('users').get();

// Get by primary key (shorthand)
final user = await laconic.table('users').find(1);

// Get first matching record (shorthand)
final admin = await laconic.table('users').firstWhere('role', 'admin');

// Get first record (throws if none found)
final user = await laconic.table('users').first();

// Get sole record (throws if none or multiple found)
final user = await laconic.table('users').where('email', 'john@example.com').sole();

// Select specific columns
final names = await laconic.table('users').select(['name', 'age']).get();

// Count records
final count = await laconic.table('users').count();

// Check if records exist
final exists = await laconic.table('users').where('id', 1).exists();

// Pluck column values
final names = await laconic.table('users').pluck('name');           // List
final map = await laconic.table('users').pluck('name', key: 'id');  // Map<id, name>

// Debug query (prints SQL + bindings, returns this)
laconic.table('users').where('active', true).dump();

// Get SQL without executing
final sql = laconic.table('users').where('age', 18, comparator: '>').toSql();
```

### Query convenience APIs (unreleased)

Relative date predicates accept one column or a list of column names:

```dart
final overdue = await laconic.table('invoices').wherePast('due_at').get();
final today = await laconic.table('invoices').whereToday('due_at').get();
final cutoff = DateTime.utc(2026, 10, 30, 12);
final due = await laconic.table('invoices')
    .whereNowOrPast(['due_at', 'review_at'], now: cutoff).get();
```

Available pairs are `wherePast/whereFuture`, `whereNowOrPast/whereNowOrFuture`,
`whereBeforeToday/whereAfterToday`, `whereTodayOrBefore/whereTodayOrAfter`, and
`whereToday`, each with its `orWhere...` variant. Strict comparisons exclude the
boundary; `NowOr...` and `TodayOr...` include it. SQL NULL does not match.
The application clock is captured once per method call (not at execution), or
supplied through `now:`. Timestamp predicates bind `yyyy-MM-dd HH:mm:ss` at second
precision; today predicates bind `yyyy-MM-dd` and compare date parts. Calendar
fields are used without timezone conversion: choose a clock matching your stored
values. SQLite timestamp TEXT should use the same SQL format for comparisons.
Multiple columns add individual AND predicates, or individual OR predicates for
OR variants. Use `whereNested` when a group is needed. An empty list is a no-op
and does not bypass the existing guard against unfiltered deletes/increments.

```dart
final base = laconic.table('users');
final active = base.clone().tap((q) => q.where('active', 1));
final total = await active.pipe((q) => q.count());
final adjusted = await active.where('id', 1).rawValue('votes + ?', [5]);
final posts = laconic.table('posts p').whereColumn('p.user_id', 'u.id');
final authors = await laconic.table('users u').whereExists(posts).get();
```

`tap` calls a synchronous query component and returns the same builder, ignoring
its result. `pipe` returns the callback result; synchronous null/void returns the
builder, while futures are passed through unchanged (including a future resolving
to null). Call `clone()` first to preserve reusable templates. All four EXISTS
variants accept an existing builder in WHERE and JOIN clauses, capturing its SQL
and bindings without modifying it; later changes to that builder do not change
the already-composed query.

`rawValue(expression, bindings)` reads one expression from the first matching
row, preserving its native driver type and returning null for no row or SQL NULL.
It replaces projections only for that read and keeps the original builder intact.
For UNION/groupLimit, reference columns exposed by the complete result. SQL
expressions are trusted code; bind user values with `?`.

### WHERE Clauses

An empty `whereIn` compiles to false and an empty `whereNotIn` to true, while
retaining the complete Boolean expression. For example,
`whereIn('id', []).orWhere('id', 1)` can still return the row with ID 1.

```dart
// Basic where
final adults = await laconic.table('users')
    .where('age', 18, comparator: '>=')
    .get();

// Multiple conditions (AND)
final results = await laconic.table('users')
    .where('age', 18, comparator: '>')
    .where('status', 'active')
    .get();

// OR conditions
final users = await laconic.table('users')
    .where('role', 'admin')
    .orWhere('role', 'moderator')
    .get();

// WHERE IN / NOT IN
final users = await laconic.table('users')
    .whereIn('id', [1, 2, 3])
    .get();

// WHERE NULL / NOT NULL
final usersWithEmail = await laconic.table('users')
    .whereNotNull('email')
    .get();

// WHERE BETWEEN
final users = await laconic.table('users')
    .whereBetween('age', min: 18, max: 30)
    .get();

// LIKE / NOT LIKE (sugar)
final matches = await laconic.table('users')
    .whereLike('name', 'John%')
    .get();

// Nested WHERE groups (parenthesized sub-conditions)
final users = await laconic.table('users')
    .where('status', 'active')
    .whereNested((q) => q.where('age', 30).orWhere('role', 'admin'))
    .get();
// SQL: WHERE status = ? AND (age = ? OR role = ?)

// Date WHERE clauses
final todayUsers = await laconic.table('users').whereToday('created_at').get();
final janUsers = await laconic.table('users').whereMonth('created_at', 1).get();
final year2025 = await laconic.table('users').whereYear('created_at', 2025).get();

// WHERE EXISTS subquery
final usersWithPosts = await laconic.table('users u')
    .whereExists((q) => q.from('posts p').whereColumn('p.user_id', 'u.id'))
    .get();

// Conditional WHERE (Laravel's when/unless)
final searchName = 'John';
final users = await laconic.table('users')
    .when(searchName.isNotEmpty, (q) => q.where('name', searchName))
    .get();
```

### JOIN Operations

```dart
// INNER JOIN
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// LEFT JOIN with WHERE + LIKE conditions
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .leftJoin(
      'posts p',
      (join) => join
          .on('u.id', 'p.user_id')
          .where('p.status', 'published')
          .whereLike('p.title', '%Dart%'),
    )
    .get();

// RIGHT JOIN
final results = await laconic.table('users u')
    .rightJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// CROSS JOIN
final results = await laconic.table('users').crossJoin('roles').get();
```

`sum()` returns `num` and returns `0` for empty or all-null input. `avg()`
returns `double?`; `min()` and `max()` return `Object?`, preserving the driver's
numeric, string, or date value. The latter three return `null` when no non-null
value matches. `first()` and `find()` still throw for missing records.

`insertUsing()`, `insertOrIgnoreUsing()`, `insertOrIgnore()`, and `upsert()` return
`Future<int>` with the database's affected row count. MySQL/MariaDB may count an
upsert update as two affected rows. `insert()` retains `Future<bool>`; empty
insert/upsert input is still rejected. `updateOrInsert()` accepts a values map
or a `(bool exists)` callback (sync or async), and returns whether a write affects
a row; an empty update map succeeds without a write. `existsOr()` and
`doesntExistOr()` now accept lazy callbacks and return `true` or the callback's
result, including an awaited result.

### Aggregates

`exists()` and `doesntExist()` retain GROUP BY and HAVING conditions.
`count()` counts groups for grouped queries, distinct rows for distinct queries,
and rows of the complete UNION. Scalar grouped aggregates (`sum`, `avg`, `min`,
`max`) return the first group; select aggregate expressions with `get()` to read
all groups.

```dart
final count = await laconic.table('users').count();
final total = await laconic.table('orders').sum('amount');
final average = await laconic.table('products').avg('price');
final highest = await laconic.table('scores').max('score');
final lowest = await laconic.table('scores').min('score');
```

### Insert / Update / Delete

```dart
// Insert
await laconic.table('users').insert([
  {'name': 'John', 'age': 25},
]);

// Insert (ignore duplicates)
await laconic.table('users').insertOrIgnore([
  {'email': 'john@example.com', 'name': 'John'},
]);

// Insert and get ID
final id = await laconic.table('users').insertGetId({
  'name': 'Jane',
  'age': 30,
});

// Upsert (insert or update on conflict)
await laconic.table('users').upsert(
  [{'email': 'john@example.com', 'name': 'John Updated'}],
  uniqueBy: ['email'],
  update: ['name'],
);

// Update (returns the affected row count)
final updated = await laconic.table('users')
    .where('id', 1)
    .update({'name': 'New Name'});

// Increment / Decrement (return the affected row count)
final incremented =
    await laconic.table('posts').where('id', 1).increment('views');
final decremented = await laconic
    .table('products')
    .where('id', 1)
    .decrement('stock', amount: 5);

// Delete (returns the affected row count)
final deleted = await laconic.table('users')
    .where('id', 99)
    .delete();

// Truncate (remove all rows, reset auto-increment)
await laconic.table('logs').truncate();

// Note: delete(), increment(), and decrement() require a WHERE clause by default
// to prevent accidental mass operations.

// Row Locking (MySQL/PostgreSQL; use inside a transaction)
final locked = await laconic.table('users')
    .where('status', 'pending')
    .lockForUpdate()   // FOR UPDATE (MySQL/PostgreSQL only)
    .get();

final shared = await laconic.table('users')
    .where('id', 5)
    .sharedLock()      // FOR SHARE (PG) / LOCK IN SHARE MODE (MySQL)
    .get();
```

### Ordering and Limiting

```dart
final users = await laconic.table('users')
    .orderBy('name')
    .orderByDesc('created_at')      // sugar for orderBy(col, direction: 'desc')
    .latest()                        // orderByDesc('created_at')
    .oldest('updated_at')            // orderBy('updated_at')
    .inRandomOrder()                 // RANDOM() ordering
    .skip(10)                        // alias for offset(10)
    .take(5)                         // alias for limit(5)
    .forPage(3, perPage: 15)        // limit(15).offset(30)
    .get();
```

### UNION

`union()` removes duplicate rows; `unionAll()` retains them. Each branch keeps
its selected columns, filters, groups, HAVING and pagination. Ordering, limit
and offset on the parent builder apply to the complete UNION. Use output column
names for that final ordering. Both branches must select compatible columns.
`get()`, `first()`, `sole()`, `value()`, `pluck()`, aggregates, `exists()`,
`toSql()` and `getBindings()` all include the UNION.

```dart
final results = await laconic.table('users')
    .where('role', 'admin')
    .union((q) => q.from('users').where('role', 'moderator'))
    .get();
```

### Subqueries

```dart
// SELECT subquery
final users = await laconic.table('users u')
    .select(['u.id'])
    .selectSub(
      (q) => q.from('posts p')
          .selectRaw('count(*)')
          .whereColumn('p.user_id', 'u.id'),
      'posts_count',
    )
    .get();

// FROM subquery / raw FROM
final active = await laconic.table('users')
    .fromSub((q) => q.from('users').where('active', 1), 'u')
    .get();

// IN subquery, with a callback or an existing builder
final authors = await laconic.table('users')
    .whereIn('id', (q) => q.from('posts').select(['user_id']))
    .get();

// JOIN subquery
final rows = await laconic.table('posts p')
    .select(['p.id', 'x.views'])
    .joinSub(
      (q) => q.from('post_stats').select(['post_id', 'views']),
      'x',
      'p.id',
      '=',
      'x.post_id',
    )
    .get();

// INSERT ... SELECT
await laconic.table('users_archive')
    .insertUsing(['id', 'name'], laconic.table('users').select(['id', 'name']));
```

### Pagination

Cursor pagination retains the query's complete `orderBy` sequence, including
mixed ascending/descending columns. The ordering tuple must be unique and all
ordering values must be selected and non-null; add a unique tie-breaker such as
`id`. `nextCursor` and `previousCursor` are `LaconicCursor?` objects containing
`parameters` and `pointsToNextItems`. Pass either object back to the same query;
rows always remain in the original order, including when fetching a previous
page. A null cursor starts the first page, so navigate only when the corresponding
cursor is non-null. Empty pages have no cursors. `hasMorePages` describes the
forward direction; `hasPreviousPages` describes the backward direction.

Single-column scalar cursor inputs remain supported. Without explicit ordering,
`column:` (default `id`) supplies ascending ordering. For `groupLimit`, the
existing ordering selects rows within each partition; `column:` orders the outer
pages. Use `fromSub()` around a group-limited query to supply a composite outer
ordering. Raw ORDER BY fragments are rejected; select an expression with an alias
and use `orderBy(alias)` instead. Selected aliases, grouped results and UNIONs
are filtered at the outer query level, preserving their result sets and bindings.

```dart
final page = await laconic.table('users').orderBy('id').paginate(2, perPage: 20);
page.data;          // List<LaconicResult>
page.total;         // total rows
page.lastPage;
page.hasMorePages;

final simple = await laconic.table('users').orderBy('id').simplePaginate(2, perPage: 20);
simple.hasMorePages;

final ordered = laconic.table('users').orderByDesc('created_at').orderBy('id');
final firstPage = await ordered.cursorPaginate(20);
if (firstPage.nextCursor != null) {
  final nextPage = await ordered.cursorPaginate(20, cursor: firstPage.nextCursor);
  if (nextPage.previousCursor != null) {
    final previousPage = await ordered.cursorPaginate(
      20, cursor: nextPage.previousCursor,
    );
  }
}
```

### Streaming

```dart
// Native database cursor
await for (final row in laconic.table('users').orderBy('id').cursor()) {
  print(row['name']);
}

// Offset or keyset chunked streams
await for (final row in laconic.table('users').orderBy('id').lazy(500)) {
  print(row['name']);
}
await for (final row in laconic.table('users').lazyById(500)) {
  print(row['name']);
}

await laconic.table('users').eachById((row) async {
  await sendWelcomeEmail(row['email']);
});
```

### JSON and Full Text

```dart
await laconic.table('users').whereJsonContains('tags', 'admin').get();
await laconic.table('users').whereJsonContains('profile->roles', 'admin').get();
await laconic.table('users').whereJsonContainsKey('profile->email').get();
await laconic.table('users').whereJsonLength('tags', 2).get();
await laconic.table('users').whereJsonOverlaps('tags', ['admin', 'member']).get();

await laconic.table('posts').whereFullText(['title', 'body'], 'dart').get();
await laconic.table('posts')
    .whereFullText(['body'], 'quick & fox', mode: 'raw', language: 'english')
    .get();
```

JSON paths and full-text availability differ per dialect; see the driver
READMEs and CHANGELOGs for details. SQLite full-text requires an FTS5 table.

### Dialect Features

| Feature | Method | MySQL | PostgreSQL | SQLite |
|---|---|---|---|---|
| Case-sensitive comparison | `whereBinary` | yes | - | - |
| Straight join | `straightJoin` | yes | falls back to JOIN | falls back to JOIN |
| Index hints | `useIndex` / `forceIndex` / `ignoreIndex` | yes | ignored | ignored |
| UPDATE ... FROM | `updateFrom` | - | yes | - |
| LATERAL join | `joinLateral` / `leftJoinLateral` | yes | yes | - |
| Per-group limit | `groupLimit` | yes | yes | yes |
| JSON overlaps | `whereJsonOverlaps` | yes | arrays/keys | arrays |
| Full text | `whereFullText` | yes | yes | FTS5 |

### Query Hooks

```dart
final laconic = Laconic(
  SqliteDriver(SqliteConfig('app.db')),
  beforeQuery: (query) => print('→ ${query.sql}'),
  afterQuery: (query, elapsed) =>
      print('← ${query.sql} (${elapsed.inMilliseconds} ms)'),
);
```

### Query identifiers and write scopes

Column and table names are quoted for the current dialect, including qualified
names and aliases. Use `Expression`, `selectRaw`, `groupByRaw`, `havingRaw`, or
`fromRaw` for SQL expressions; strings such as `COUNT(*)` are now identifiers.
JSON selectors work in ordinary predicates and projections, and in update keys:

```dart
await laconic.table('users').where('settings->enabled', true).update({
  'settings->name': 'Alice',
  'settings->notifications->email': false,
});
final names = await laconic.table('users').pluck('settings->name');
```

`update`, `delete`, and increments retain JOIN, ORDER BY, LIMIT, and OFFSET when
the dialect supports them. MySQL/MariaDB reject nonzero write offsets and
JOIN combined with ORDER BY/LIMIT. MariaDB 10.11 also rejects ORDER BY/LIMIT
on aliased deletes. SQL Server supports JOIN and TOP limits but
rejects ordered writes and nonzero offsets. SQLite uses rowid and PostgreSQL
uses row identities to select the write scope; scoped SQLite writes require a
rowid table. Grouping, HAVING, UNION, DISTINCT, derived/raw FROM sources,
`groupLimit`, index hints, and locks are rejected for writes instead of ignored.
`updateOrInsert` updates at most one matching row.

### Chunking Large Results

`chunkByIdDesc` and `lazyByIdDesc` use the same cursor rules in descending order.
`orderedChunkById(count, callback, descending: true)` selects the direction
explicitly. These methods replace old ordering, preserve the total limit and
initial offset, and page the full UNION/groupLimit result. The cursor must be
selected, non-null and unique; missing cursor columns throw `LaconicException`.
Callbacks can be async and stop with `false`; cancelling a lazy stream prevents
subsequent chunk queries. Source queries remain unchanged.

```dart
await laconic.table('users').chunkByIdDesc(100, (users, page) async {
  await processBatch(users);
});
await for (final user in laconic.table('users').lazyByIdDesc(100)) {
  await processUser(user);
}
final List<String> emails = await laconic.table('users').orderBy('id')
    .chunkMap<String>((row) async => row['email'] as String, count: 100);
```

`chunkMap<T>` requires ordering, awaits each mapping sequentially and collects a
`List<T>`. Null/false mapping results are values, not stop signals. Source rows
are fetched in chunks, but the returned list retains all mapped results in memory.

`chunkById` reads in ascending order of a unique, non-null cursor column
(default `id`). It replaces existing ordering, applies an initial offset only
to the first batch, and requires the cursor column in the selected result.
`column` chooses the SQL cursor (for example `u.id`); `alias` names its selected
result column (for example `cursor_id`).
Existing OR filters and UNION branches are included in cursor pagination.
All chunk sizes must be positive. `chunk()` and `each()` use OFFSET pagination;
`chunkById()` advances by the last cursor value. `chunk`, `each`, and `lazy`
require an explicit `orderBy`. All chunked readers preserve the total limit and
initial offset without mutating the original query. `chunk`/`chunkById` callbacks
accept `(rows)` or `(rows, page)` (one-based); `each`/`eachById` accept `(row)` or
`(row, index)` (zero-based). Return `false` to stop; these methods return `false`
when stopped and `true` on completion. Existing one-argument async callbacks work.

```dart
// Process 100 records at a time
await laconic.table('users').orderBy('id').chunk(100, (users) async {
  for (final user in users) {
    await processUser(user);
  }
});

// ID-based chunking (avoids large OFFSET)
await laconic.table('users').chunkById(100, (users) async {
  // ...
});

// Per-row callback with automatic chunking
await laconic.table('users').orderBy('id').each((user) async {
  await sendWelcomeEmail(user['email']);
});

// Clone builder for reusable query scopes
final activeQuery = laconic.table('users').where('active', true);
final count = await activeQuery.clone().count();
final results = await activeQuery.clone().get();
```

### Transactions

Await every query inside the transaction callback. MySQL and PostgreSQL pin
queries to one connection/session per driver instance; calls through another
driver keep that driver's own connection. SQLite queues overlapping transactions
and unrelated queries on its single connection. Nested transactions on the same
driver instance throw `LaconicException`; savepoints are not created automatically.

```dart
await laconic.transaction(() async {
  final userId = await laconic.table('users').insertGetId({
    'name': 'Test User',
  });

  await laconic.table('posts').insert([
    {'user_id': userId, 'title': 'First Post'},
  ]);
});
```

## Architecture

### Package Structure

```
laconic/                     # Workspace root
├── packages/
│   ├── laconic/             # Core package
│   │   └── lib/src/
│   │       ├── laconic.dart          # Main entry point
│   │       ├── database_driver.dart  # Abstract driver interface
│   │       ├── grammar/              # SQL grammar (abstract)
│   │       └── query_builder/        # Query builder
│   ├── laconic_sqlite/      # SQLite driver
│   ├── laconic_mysql/       # MySQL driver
│   └── laconic_postgresql/  # PostgreSQL driver
```

### Core Components

1. **Laconic** - Main entry point, delegates to driver
2. **DatabaseDriver** - Abstract interface for database drivers
3. **SqlGrammar** - Abstract base for SQL generation
4. **QueryBuilder** - Fluent query builder

### Custom Drivers

You can create custom drivers by implementing `DatabaseDriver`:

```dart
class MyDriver implements DatabaseDriver {
  @override
  SqlGrammar get grammar => MyGrammar();

  @override
  Future<List<LaconicResult>> select(String sql, [List<Object?> params = const []]) async {
    // Implementation
  }

  @override
  Stream<LaconicResult> selectStream(String sql, [List<Object?> params = const []]) async* {
    // Optional: use a native cursor. The default buffers select().
    yield* Stream.fromIterable(await select(sql, params));
  }

  // Implement other methods...
}
```

## Testing

Run from the workspace root. Core and SQLite tests do not require Docker.
MySQL/PostgreSQL tests use the local databases in `docker-compose.yml`, on
ports 3306 and 5433 respectively.

```bash
dart pub get
dart analyze

# Tests that do not require Docker
dart test packages/laconic/test packages/laconic_sqlite/test

# Wait for healthy databases, then run all four packages
docker compose up -d --wait
dart test packages/laconic/test packages/laconic_sqlite/test packages/laconic_mysql/test packages/laconic_postgresql/test --concurrency=1
docker compose down
```

Coverage includes query semantics, duplicate column names, fragmented packets,
large TLS results, concurrent commands, transaction isolation and server-side
statement disposal.

## Upgrading to the current release

- The core is `6.0.0`, SQLite is `4.0.0`, MySQL is `5.0.0`, and PostgreSQL is `4.0.0`. Update the core and your chosen drivers together.
- Published 6.0 uses nullable numeric aggregates; see the unreleased return contracts above for this workspace.
- `insert()` returns `Future<bool>`.
- `where('column', null)` now compiles to `IS NULL` instead of `= NULL`.
- Custom grammars overriding `SqlGrammar.compileSelect` must add the new optional parameters (`selectBindings`, `groupBindings`, `distinctColumns`, `fromSubquery`, `fromAlias`, `indexHints`).
- Custom drivers using `implements DatabaseDriver` must implement `selectStream`; the default implementation buffers `select()`.
- New APIs include pagination/streaming, subqueries, JSON/full text, `groupLimit`, query hooks and the dialect methods listed above.
- Existing `first()` / `find()` behavior is unchanged (they throw); use `firstOrNull()` / `findOrNull()` for nullable results.

Release notes: [core](packages/laconic/CHANGELOG.md), [SQLite](packages/laconic_sqlite/CHANGELOG.md), [MySQL](packages/laconic_mysql/CHANGELOG.md), [PostgreSQL](packages/laconic_postgresql/CHANGELOG.md). Publish steps: [RELEASE.md](RELEASE.md).

## Migration from 1.x

Before (1.x):
```dart
import 'package:laconic/laconic.dart';
final laconic = Laconic.mysql(MysqlConfig(...));
```

After (2.0 and later):
```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
final laconic = Laconic(MysqlDriver(MysqlConfig(...)));
```

## License

MIT License

## Contributing

Issues and Pull Requests are welcome!

## Schema and migrations (unreleased)

Includes full-text indexes on MySQL/MariaDB and PostgreSQL, index renaming and
deletion, column comments/collations, timestamp modifiers and generated columns.
See SCHEMA.md for dialect support and the third-party driver upgrade contract.

Supports `change()`, typed table/view/column/index/foreign-key metadata, and
atomic SQLite table rebuilds. See the schema guide for transaction restrictions.
Blueprint includes foreign-key, soft-delete and morph shortcuts, plus enum/SET,
JSONB/ULID, temporal, binary, network and spatial types with explicit dialect limits.

The core now provides `db.schema` for table creation, alteration, and inspection.
DDL uses the existing `SqlGrammar`; concrete dialects live in their driver packages.
The core also includes `Migration`, `Migrator`, and the `dart run laconic` CLI.
CLI commands include reset/refresh/fresh, batch rollback, SQL previews, and
production `--force` protection.
See [Schema Builder and driver extension](SCHEMA.md) and the
[migration guide](packages/laconic/MIGRATIONS.md).
