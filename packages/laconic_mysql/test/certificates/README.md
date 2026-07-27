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
