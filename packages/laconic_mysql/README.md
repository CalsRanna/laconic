# laconic_mysql

MySQL driver for the [Laconic](https://pub.dev/packages/laconic) query builder.

[中文文档](README_ZH.md)

## Installation

The package declares Dart SDK `>=3.7.0 <4.0.0`. Running the full workspace
also requires Dart 3.10 for its SQLite dependency.

```yaml
dependencies:
  laconic: ^6.0.0
  laconic_mysql: ^5.0.0
```

## Usage

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
    // maxConnections: 10, // optional, default 10
    // useSsl: true, // optional, default true
  )));

  // Query users
  final users = await laconic.table('users').where('active', true).get();

  // Insert data
  final id = await laconic.table('users').insertGetId({
    'name': 'John',
    'age': 25,
  });

  // Update data and get the matched row count
  final updated =
      await laconic.table('users').where('id', id).update({'age': 26});

  // Delete data and get the affected row count
  final deleted = await laconic.table('users').where('id', id).delete();

  // Don't forget to close
  await laconic.close();
}
```

## Configuration

`MysqlConfig` accepts the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `database` | `String` | required | Database name |
| `host` | `String` | `'127.0.0.1'` | MySQL host address |
| `port` | `int` | `3306` | Connection port |
| `username` | `String` | `'root'` | Connection username |
| `password` | `String` | required | Connection password |
| `maxConnections` | `int` | `10` | Maximum connections in the pool |
| `useSsl` | `bool` | `true` | Negotiate TLS with the server |
| `allowBadCertificates` | `bool` | `false` | Accept an invalid TLS certificate; development only |
| `securityContext` | `SecurityContext?` | `null` | Custom trusted certificates for TLS |
| `allowPublicKeyRetrieval` | `bool` | `true` | Request the server RSA key for non-TLS `caching_sha2_password` authentication |
| `serverPublicKey` | `String?` | `null` | Pinned server RSA public key in PEM format |
| `connectTimeout` | `Duration` | `10 seconds` | Maximum time for connection and authentication |
| `commandTimeout` | `Duration` | `10 seconds` | Maximum time for a database command |

## Connection security

TLS is enabled by default. A server certificate signed by a system-trusted CA
works without additional configuration. For a private CA, create a
`SecurityContext` that trusts it:

```dart
import 'dart:io';

final context = SecurityContext(withTrustedRoots: true)
  ..setTrustedCertificates('certificates/mysql-ca.pem');

final config = MysqlConfig(
  database: 'my_database',
  password: 'password',
  securityContext: context,
);
```

`allowBadCertificates: true` disables certificate validation and is intended
only for isolated development environments. Do not enable it in production.

MySQL 8.4 and later commonly use `caching_sha2_password`. With
`useSsl: false`, Laconic encrypts the password using the server RSA key. Public
key retrieval is enabled by default for compatibility, but retrieval on an
untrusted network is vulnerable to an active man-in-the-middle attack. Set
`serverPublicKey` to a trusted PEM key and
`allowPublicKeyRetrieval: false` when TLS cannot be used on such a network.

```dart
import 'dart:io';

final publicKey =
    await File('certificates/mysql-server-public-key.pem').readAsString();

final config = MysqlConfig(
  database: 'my_database',
  password: 'password',
  useSsl: false,
  serverPublicKey: publicKey,
  allowPublicKeyRetrieval: false,
);
```

For a trusted local or private network where key pinning is not required,
`MysqlConfig(..., useSsl: false)` can retrieve the server public key
automatically. This protects the password from passive observation, but it
does not authenticate the server. Prefer TLS whenever possible.

## Upgrading from 4.x to 5.0

- Requires `laconic: ^6.0.0`.
- `selectStream` uses the client's streaming result set; `cursor()`, `lazy()` and `lazyById()` are available through the core builder.
- New dialect methods: JSON contains/key/length/overlaps with `->` paths, full-text search, `whereBinary`, `straightJoin`, index hints, LATERAL joins, `insertOrIgnoreUsing` and `groupLimit`.
- Commands complete in order on each connection; transaction queries also serialize preparation, cache access and command execution.
- Same-instance nested transactions now fail explicitly. Separate driver instances retain their own database and transaction context.
- See the [CHANGELOG](CHANGELOG.md) for the complete release notes.

## Migrating from 2.x

- TLS is now enabled by default. Add `useSsl: false` only if your trusted MySQL
  server does not support TLS.
- Client-specific `MySQL*Exception` classes are no longer public. Catch
  `LaconicException` from driver operations instead.
- Do not import `package:laconic_mysql/src/client/...`; the embedded client is
  an internal implementation detail.

## Connection Pooling

The driver maintains a small internal connection pool:

- Connections are created lazily on first use
- Each non-transaction query borrows a connection and **always** returns it, including when SQL errors are thrown
- Transactions pin one connection for the duration of the callback via Zone isolation
- Call `close()` to shut down the pool when the application exits

This avoids connection-slot exhaustion after repeated query failures.

## Result handling and performance

Parameterized queries use the binary protocol with a prepared-statement cache
of up to 50 entries per connection; queries without parameters use the text
protocol. Fragmented packets are assembled incrementally into a buffer sized
from their header, avoiding repeated copies of all received data for large fields
and TLS fragments. Typed row values share column metadata while preserving
mutable results and duplicate-column behavior.

## Update Results

MySQL updates use matched-row semantics. An update whose `WHERE` clause finds
one row returns `1` even when the submitted values are already stored. A
missing row returns `0`. This lets callers distinguish an unchanged existing
record from a record that was concurrently deleted.

The package maintains its MySQL client implementation internally. Applications
do not need to depend on or override `mysql_client`.

## Query Listener

You can add a query listener for debugging:

```dart
final laconic = Laconic(
  MysqlDriver(MysqlConfig(
    database: 'my_database',
    password: 'password',
  )),
  listen: (query) {
    print('SQL: ${query.sql}');
    print('Bindings: ${query.bindings}');
  },
);
```

## Transactions

Await every query inside the transaction callback. Nested transactions on the
same driver instance throw `LaconicException`; savepoints are not created
automatically. Different driver instances retain independent transaction contexts.

Transaction queries are pinned to one connection/session and execute serially.
You can await queries with `Future.wait`; each query receives its own result.
Calls through another driver instance use that instance's own connection.

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

## License

MIT License
