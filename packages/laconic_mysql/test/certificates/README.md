# Test certificates

These PEM files are fixtures for the `laconic_mysql` TLS and
`caching_sha2_password` test suites:

- `tls-ca-cert.pem` is the test certificate authority.
- `tls-server-cert.pem` and `tls-server-key.pem` identify the loopback TLS
  server used by the tests.
- `mysql-rsa-public-key.pem` is the public key used by non-TLS MySQL
  authentication tests.

The certificates and private key are intentionally committed so the tests are
reproducible. They are public, test-only credentials, are not trusted by
default, and must never be used by a production or externally reachable
service.

## Running the fixture tests

From the workspace root:

```bash
dart test packages/laconic_mysql/test/mysql_tls_test.dart packages/laconic_mysql/test/caching_sha2_auth_test.dart
```

The TLS tests create a loopback test server; the RSA tests inspect authentication
payloads. These suites do not require a Docker database.

The [large-result and concurrency regressions](../performance_regression_test.dart)
use the MySQL container from the workspace's `docker-compose.yml`. Their TLS
connections use the container's certificate, rather than these PEM fixtures.
Start the container and run them from the workspace root:

```bash
docker compose up -d --wait mysql
dart test packages/laconic_mysql/test/performance_regression_test.dart
```
