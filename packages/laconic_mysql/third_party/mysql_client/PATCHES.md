# Embedded mysql_client fork

`laconic_mysql` embeds the Dart sources from `mysql_client` 0.0.27 under
`lib/src/client/` as a private implementation detail. The upstream license is
preserved in this directory.

Local changes:

- package imports use the private `package:laconic_mysql/src/client/` namespace;
- both plain and TLS handshakes request `CLIENT_FOUND_ROWS`, making UPDATE
  results report rows matched by the `WHERE` clause;
- the public `laconic_mysql` API exports the client exception types needed for
  driver-specific error handling, but does not expose connection/protocol APIs.

Upstream: https://github.com/zim32/mysql.dart/tree/0.0.27
