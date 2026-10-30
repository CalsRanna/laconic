## Unreleased

- Inherit `change()` and typed structure metadata from the matching MySQL grammar;
  default values retain MariaDB's native expression representation.
- Requires the matching unreleased core schema contract; coordinate published
  minimum core/driver versions before release.

- Inherit identifier quoting, JSON selectors/path updates, and write scopes from
  MySQL; reject nonzero write offsets and JOIN with ORDER BY/LIMIT. Compile
  aliased DELETE using MariaDB 10.11 syntax and reject ORDER BY/LIMIT on it.
- **Breaking:** adopt the matching unreleased core query compiler contract and
  chunking semantics. Use `Expression`/`*Raw` for SQL expressions. Existing
  version numbers are retained until a coordinated core/driver release.

- Support core Schema Builder operations through the shared MySQL compilation
  implementation, verified against MariaDB.

## 1.0.0 (unreleased)

- Initial MariaDB 10.11+ driver, grammar and configuration.
- Parameterized CRUD, subqueries, pagination, transactions and row streaming.
- Shared query regressions and real database connection/write tests.
- Uses the Laconic 6.x workspace core; no migration from an earlier driver version.
