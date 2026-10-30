# Laconic

[中文文档](README_ZH.md)

A Laravel-style SQL query builder for Dart, supporting MySQL, SQLite, and PostgreSQL databases.

This is the core package that provides the query builder API and abstract driver interface. You'll also need a driver package for your database:

- [laconic_sqlite](https://pub.dev/packages/laconic_sqlite) - SQLite driver
- [laconic_mysql](https://pub.dev/packages/laconic_mysql) - MySQL driver
- [laconic_postgresql](https://pub.dev/packages/laconic_postgresql) - PostgreSQL driver

## Features

- **Laravel-style API** - Familiar query builder syntax with 130+ methods
- **Subqueries** - SELECT/FROM/JOIN subqueries, IN subqueries, insert-using and UNION
- **Pagination and Streaming** - `paginate`, `simplePaginate`, `cursorPaginate`, `cursor`, `lazy`, `lazyById`
- **JSON and Full Text** - JSON conditions with `->` paths; MySQL/PostgreSQL full text; SQLite FTS5
- **Dialect Features** - MySQL binary/index hints/straight joins, PostgreSQL `updateFrom`/LATERAL, `groupLimit`
- **Fluent Interface** - Chainable methods for elegant query building
- **Parameterized Queries** - Bound values for query parameters; raw SQL and identifiers must be trusted
- **Transaction Support** - Complete transaction management
- **Query Hooks** - `beforeQuery` / `afterQuery` timing callbacks
- **Driver Abstraction** - Clean separation between query builder and database implementations

## Installation

The core declares Dart SDK `>=3.7.0 <4.0.0`. Running the whole workspace or
the SQLite example below requires Dart 3.10 or a later 3.x SDK with the currently
resolved `sqlite3 3.3.4` dependency.

```yaml
dependencies:
  laconic: ^6.0.0
  laconic_sqlite: ^4.0.0  # Or your preferred driver
```

## Quick Start

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

## Query Builder

### Select

```dart
// Get all records
final users = await laconic.table('users').get();

// Get first record
final user = await laconic.table('users').first();

// Select specific columns
final names = await laconic.table('users').select(['name', 'age']).get();

// Distinct
final roles = await laconic.table('users').distinct().select(['role']).get();
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

// WHERE IN
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

// WHERE column comparison
final users = await laconic.table('users')
    .whereColumn('created_at', 'updated_at', comparator: '<')
    .get();

// Nested WHERE groups
final users = await laconic.table('users')
    .where('status', 'active')
    .whereNested((q) => q.where('age', 30).orWhere('role', 'admin'))
    .get();
// SQL: WHERE status = ? AND (age = ? OR role = ?)

// Date WHERE clauses
final todayUsers = await laconic.table('users').whereToday('created_at').get();
final janUsers = await laconic.table('users').whereMonth('created_at', 1).get();

// WHERE EXISTS subquery
final usersWithPosts = await laconic.table('users u')
    .whereExists((q) => q.from('posts p').whereColumn('p.user_id', 'u.id'))
    .get();

// Debug query
final sql = laconic.table('users').where('active', true).toSql();
print(sql); // SELECT * FROM users WHERE active = ?
```

### Retrieving Single Records

```dart
// Get by primary key (shorthand)
final user = await laconic.table('users').find(1);

// Nullable retrieval
final maybeUser = await laconic.table('users').findOrNull(1);
final maybeFirst = await laconic.table('users').firstOrNull();
final fallback = await laconic.table('users').firstOr(
  () => LaconicResult.fromMap({'id': 0, 'name': 'guest'}),
);

// Get first matching record (shorthand)
final admin = await laconic.table('users').firstWhere('role', 'admin');

// Get first record (throws if none found; firstOrFail() is an alias)
final user = await laconic.table('users').first();

// Get sole record (throws if none or multiple found)
final user = await laconic.table('users').where('email', 'john@example.com').sole();

// Get a single column value (null if none found)
final email = await laconic.table('users').where('name', 'John').value('email');

// Pluck column values
final names = await laconic.table('users').pluck('name');           // List
final map = await laconic.table('users').pluck('name', key: 'id');  // Map<id, name>
```

### JOIN Operations

```dart
// INNER JOIN
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// LEFT JOIN with conditions
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .leftJoin(
      'posts p',
      (join) => join
          .on('u.id', 'p.user_id')
          .where('p.status', 'published'),
    )
    .get();

// RIGHT JOIN
final results = await laconic.table('users u')
    .rightJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// CROSS JOIN
final results = await laconic.table('users')
    .crossJoin('roles')
    .get();
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

// Note: delete(), increment(), and decrement() require a WHERE clause by default
// to prevent accidental mass operations. To explicitly allow without WHERE:
// await laconic.table('users').delete(allowWithoutWhere: true);

// Truncate (remove all rows, reset auto-increment)
await laconic.table('logs').truncate();
```

### Ordering and Limiting

```dart
final users = await laconic.table('users')
    .orderBy('name')
    .orderByDesc('created_at')      // sugar for orderBy(col, direction: 'desc')
    .latest()                        // orderByDesc('created_at')
    .oldest('updated_at')            // orderBy('updated_at')
    .inRandomOrder()                 // RANDOM() ordering
    .skip(10)                        // alias for offset
    .take(5)                         // alias for limit
    .forPage(3, perPage: 15)        // limit(15).offset(30)
    .get();
```

### Row Locking

Row locks require MySQL or PostgreSQL and should be used inside a transaction.
SQLite does not support these row-lock clauses.

```dart
// FOR UPDATE — prevent other transactions from modifying selected rows
final users = await laconic.table('users')
    .where('status', 'pending')
    .lockForUpdate()
    .get();

// FOR SHARE (PostgreSQL) / LOCK IN SHARE MODE (MySQL)
final users = await laconic.table('users')
    .where('id', 5)
    .sharedLock()
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
final results = await laconic.table('users').select(['id', 'name'])
    .where('role', 'admin')
    .union((q) => q.from('users').select(['id', 'name']).where('role', 'moderator'))
    .orderBy('id').limit(20).get();
```

### Subqueries

Scalar subqueries are also accepted as the first argument of `where` / `orWhere`,
by `orderBy` / `orderByDesc`, and as values in `update` (`updateFrom` on PostgreSQL).
Pass an existing builder or a synchronous builder callback. WHERE and ORDER BY
capture the subquery when composed; UPDATE captures it when called. Source
builders and input maps are not modified. Subqueries must produce one column and
at most one row, following the database's scalar-subquery rules.

```dart
final latestTotal = laconic.table('orders o').selectRaw('max(o.total)')
    .whereColumn('o.user_id', 'u.id');
final users = await laconic.table('users u')
    .where(latestTotal, 100, comparator: '>')
    .orderByDesc(latestTotal).get();
await laconic.table('users u').where('u.id', 1)
    .update({'last_order_total': latestTotal});
```

For cursor pagination, select the subquery with `selectSub(..., 'alias')` and
order by that alias instead of ordering directly by the subquery.

```dart
final users = await laconic.table('users u')
    .select(['u.id'])
    .selectSub(
      (q) => q.from('posts p')
          .selectRaw('count(*)')
          .whereColumn('p.user_id', 'u.id'),
      'posts_count',
    )
    .get();

final active = await laconic.table('users')
    .fromSub((q) => q.from('users').where('active', 1), 'u')
    .get();

final authors = await laconic.table('users')
    .whereIn('id', (q) => q.from('posts').select(['user_id']))
    .get();

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

await laconic.table('users_archive')
    .insertUsing(['id', 'name'], laconic.table('users').select(['id', 'name']));
```

### Pagination and Streaming

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
page.data;
page.total;
page.lastPage;
page.hasMorePages;

final simple = await laconic.table('users').simplePaginate(2, perPage: 20);
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

await for (final row in laconic.table('users').orderBy('id').cursor()) {
  print(row['name']);
}
await for (final row in laconic.table('users').orderBy('id').lazy(500)) {
  print(row['name']);
}
await for (final row in laconic.table('users').lazyById(500)) {
  print(row['name']);
}
```

### JSON, Full Text and Dialect Methods

```dart
await laconic.table('users').whereJsonContains('tags', 'admin').get();
await laconic.table('users').whereJsonContains('profile->roles', 'admin').get();
await laconic.table('users').whereJsonContainsKey('profile->email').get();
await laconic.table('users').whereJsonLength('tags', 2).get();
await laconic.table('users').whereJsonOverlaps('tags', ['admin']).get();

await laconic.table('posts').whereFullText(['title', 'body'], 'dart').get();

await laconic.table('users').whereBinary('name', 'John').get(); // MySQL
await laconic.table('users').useIndex('idx_name').get();       // MySQL
await laconic.table('accounts').updateFrom('balances', {       // PostgreSQL
  'amount': Expression('balances.amount'),
});
```

Driver READMEs document availability and dialect-specific behavior.

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

## Results and errors

`LaconicResult` supports `row['column']`, `row.columns`, `row.values` and
`row.toMap()`. Driver results share column metadata and a name-to-index map;
column lookup uses that index until the row's mutable `columns` list is requested.
After that, lookup scans the row's list so edits remain visible. Both `columns`
and `values` remain mutable. Duplicate names keep their first position and last
value. Custom drivers can use `LaconicResult.fromRows(columns, rows)`; it retains
each value list when column names are unique.

Driver failures are reported as `LaconicException`. Besides `message`, the
optional `driver` and `code` fields identify the backend and its error code.
Use the backend together with the code when handling an error; codes may be null.

## Custom Drivers

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

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    // Implementation
  }

  @override
  Future<int> affectingStatement(
    String sql,
    [List<Object?> params = const []],
  ) async {
    // Execute UPDATE/DELETE and return the affected row count
  }

  @override
  Future<int> insertAndGetId(String sql, [List<Object?> params = const []]) async {
    // Implementation
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    // Implementation
  }

  @override
  Future<void> close() async {
    // Implementation
  }
}
```

## Upgrading to 6.0

- Install the core and driver versions shown above: SQLite/PostgreSQL use the 4.0 series and MySQL uses the 5.0 series.
- Published 6.0 uses nullable numeric aggregates; see the unreleased return contracts above for this workspace.
- `insert()` returns `Future<bool>`.
- `where('column', null)` compiles to `IS NULL`.
- `SqlGrammar.compileSelect` has new optional parameters; custom overrides must add them.
- Custom `DatabaseDriver` implementations must implement `selectStream`.
- `first()` / `find()` still throw; use `firstOrNull()` / `findOrNull()` for nullable results.

See the [CHANGELOG](CHANGELOG.md) for the full release notes.

## License

MIT License

## Schema Builder (unreleased)

Blueprint supports table engines, default charsets/collations, table comments and
session temporary tables where supported. Temporary-only drops preserve
same-named permanent tables; see the schema guide for connection-pool usage.

Includes full-text indexes on MySQL/MariaDB and PostgreSQL, index renaming and
deletion, column comments/collations, timestamp modifiers and generated columns.
See the schema guide for dialect support and the third-party driver upgrade contract.

Supports `change()`, typed table/view/column/index/foreign-key metadata, and
atomic SQLite table rebuilds. See the schema guide for transaction restrictions.
Blueprint includes foreign-key, soft-delete and morph shortcuts, plus enum/SET,
JSONB/ULID, temporal, binary, network and spatial types with explicit dialect limits.

`Laconic.schema` exposes the core Schema Builder. SQL compilation stays in
`SqlGrammar`, with concrete behavior supplied by the selected driver. See
[the schema guide](../../SCHEMA.md) for supported operations and custom drivers.
The core also exports `Migration` and `Migrator` and provides the
`dart run laconic` CLI. See the [migration guide](MIGRATIONS.md).
Commands include reset/refresh/fresh, batch rollback, SQL previews, and production
`--force` protection.
Applications supply their chosen database driver; the core has no driver dependencies.
