## Unreleased

- Implement `change()` with default-constraint discovery/replacement and native
  ALTER COLUMN. Index/computed-column dependencies remain database restrictions.
- Add typed catalog metadata with ordered keys and identity/computed details.
- Requires the matching unreleased core schema contract; coordinate published
  minimum core/driver versions before release.

- Quote query identifiers and support JSON scalar selectors/path updates. Retain
  joined writes and TOP limits; reject ordered writes and nonzero write offsets.
- **Breaking:** adopt the matching unreleased core query compiler contract and
  chunking semantics. Use `Expression`/`*Raw` for SQL expressions. Existing
  version numbers are retained until a coordinated core/driver release.

- Implement core Schema Builder operations, identity columns, Unicode defaults,
  namespace-aware inspection, and transactional migration DDL.

## 1.0.0 (unreleased)

- Initial SQL Server 2022+ driver, grammar and configuration.
- Parameterized CRUD, subqueries, pagination, transactions and row streaming.
- Shared query regressions and real database connection/write tests.
- Uses the Laconic 6.x workspace core; no migration from an earlier driver version.
