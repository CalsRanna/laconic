# laconic_sqlserver

SQL Server **2022+** support for Laconic, using the community `mssql` Dart client.
Use database compatibility level **160 or later**. The driver provides lazy
connection pooling, positional parameter binding, transactions and native row streaming.

This new package is under development in this workspace and has not been published.
It requires the workspace core's new `SqlGrammar.compileAggregateExpression`
hook; publish the updated core before publishing this driver.

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlserver/laconic_sqlserver.dart';

final db = Laconic(SqlserverDriver(SqlserverConfig(
  host: '127.0.0.1',
  database: 'app',
  username: 'app',
  password: 'password',
)));
try {
  final page = await db.table('users').orderBy('id').paginate(1, perPage: 20);
  print(page.data);
} finally {
  await db.close();
}
```

TLS and certificate validation are enabled by default. `allowBadCertificates`
is an explicit opt-in for development servers with self-signed certificates.
`useSsl: false` is intended for local test servers. Other options include
`maxConnections`, `connectTimeout`, and `acquireTimeout`. Authentication currently
uses SQL Server username/password credentials.

## SQL behavior

- `toSql()` emits `?` placeholders. The driver converts them to named parameters
  for the client's parameterized RPC call, preserving strings, quoted identifiers
  and comments. Values are never interpolated into executable SQL.
- `limit` uses `TOP`; offset pagination uses `OFFSET/FETCH`. Add `orderBy` for
  stable paging. An unspecified order does not guarantee a stable row sequence.
- `insertGetId` uses `OUTPUT inserted.id` and requires an integer ID. SQL Server
  restricts direct OUTPUT on tables with enabled INSERT triggers; this convenience
  method does not support those tables.
- `upsert` uses `MERGE ... WITH (HOLDLOCK)` with explicit `uniqueBy` columns.
  Provide a corresponding primary/unique key. An empty update list inserts only
  missing keys. Duplicate source keys retain SQL Server's native error behavior.
- `avg()` casts its input to float to preserve fractional averages of integers.
- Lateral joins use `CROSS APPLY` / `OUTER APPLY`. Tuple comparisons expand into
  scalar predicates. Date filtering, UNION, grouping and keyset paging are supported.
- `lockForUpdate()` uses `UPDLOCK, ROWLOCK`; `sharedLock()` uses `HOLDLOCK, ROWLOCK`.
  Use them inside a transaction. Raw `lock(...)` takes a table-hint body, e.g.
  `readpast, updlock`, without `WITH (...)`. Locks on derived tables are rejected.
- JSON key checks use `JSON_PATH_EXISTS`. JSON membership and overlaps support
  scalar values and flat scalar candidate arrays against JSON arrays, including
  `column->arrayPath`. Object/nested-array candidates and raw JSON candidate
  expressions throw. JSON length counts elements at the selected array/object path.
- Full text uses `FREETEXT` by default, or `CONTAINS` with `mode: 'boolean'`.
  Boolean searches use SQL Server CONTAINS syntax. A full-text index is required.

`insertOrIgnore`, `insertOrIgnoreUsing`, `whereBinary`, MySQL index hints,
`straightJoin`, and `updateFrom` throw `LaconicException`; unsupported operations
are not silently approximated.

## Transactions and streaming

Transactions pin one connection and serialize concurrent queries on it. Nested
transactions and reuse of an expired transaction zone are rejected. Rollback
errors include the original failure. Server exceptions expose
`driver == 'sqlserver'` and the SQL Server error code.

Streams retain their connection until completion. Cancelling a stream drains the
remaining protocol rows without retaining them before returning the connection;
this keeps an in-progress transaction usable. Cancellation can therefore wait for
the server query to finish. `connectTimeout` covers connection establishment;
there is currently no driver-level query timeout or query cancellation API.

## Tests

```sh
docker compose up -d --wait sqlserver
dart test packages/laconic_sqlserver/test --concurrency=1
```

The suite creates `testdb` if absent on the local test instance. Defaults:
`127.0.0.1:1433`, login `sa`, password `Laconic_test_123!`, TLS disabled.
Override `SQLSERVER_HOST`, `SQLSERVER_PORT`, `SQLSERVER_USER`,
`SQLSERVER_PASSWORD`, `SQLSERVER_SSL`, and `SQLSERVER_TRUST_CERTIFICATE` as needed.
Set `SQLSERVER_DATABASE` to use an existing dedicated test database without
creating one. Tests create and drop their own tables.

The Docker image uses `linux/amd64`. Running it on Apple Silicon relies on
emulation; Microsoft's supported container hosts are Linux x86-64.
