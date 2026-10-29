# laconic_mariadb

MariaDB **10.11+** support for Laconic. This package reuses the MySQL protocol
client, prepared statements, connection pool and transaction implementation from
`laconic_mysql`, and provides a MariaDB-specific grammar and error identifier.

This new package is under development in this workspace and has not been published.

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mariadb/laconic_mariadb.dart';

final db = Laconic(MariadbDriver(MariadbConfig(
  host: '127.0.0.1',
  database: 'app',
  username: 'app',
  password: 'password',
)));
try {
  final users = await db.table('users').where('active', 1).get();
  print(users);
} finally {
  await db.close();
}
```

TLS is enabled by default. Use `securityContext` for a private CA, and
`useSsl: false` only for a local test server without TLS. Configuration also
supports `maxConnections`, `connectTimeout`, and `commandTimeout`.

## Supported behavior

- CRUD, generated IDs, affected row counts, upsert and insert-ignore.
- Subqueries, joins, UNION, grouping, pagination, cursor and chunked reading.
- JSON contains/key/length/overlaps, full text, binary comparisons and index hints.
- Transactions pin one pooled connection; nested transactions are rejected.
- Server errors expose `LaconicException.driver == 'mariadb'` and the server code.

MariaDB does not accept the MySQL `JOIN LATERAL` syntax, so lateral joins throw
`LaconicException` during compilation. `updateFrom` remains PostgreSQL-specific.
The shared protocol client supports `mysql_native_password` and
`caching_sha2_password`; MariaDB-specific authentication plugins such as
`ed25519` and `unix_socket` are not implemented. Use a compatible TCP account.
The 10.11 minimum includes the `JSON_OVERLAPS` function introduced in 10.9.

## Tests

From the workspace root:

```sh
docker compose up -d --wait mariadb
dart test packages/laconic_mariadb/test --concurrency=1
```

The test server defaults to `127.0.0.1:3307`, database `testdb`, user/password
`root`/`root`. Override `MARIADB_HOST`, `MARIADB_PORT`, `MARIADB_DATABASE`,
`MARIADB_USER`, and `MARIADB_PASSWORD` for another test instance.
