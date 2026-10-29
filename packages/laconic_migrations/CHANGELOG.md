## 1.0.0 (Unreleased)

- Add explicit `Migration` registration and `Migrator` execution using Laconic.
- Track successful migrations and batches; support status, rollback, and reset.
- Wrap each migration and history update in a transaction when supported, with
  per-migration opt-out. Preserve records when rollback fails.
- Preflight missing rollback definitions and reject overlapping instance runs.
- Validate the workflow against SQLite, MySQL, MariaDB, PostgreSQL, and SQL Server.
- Requires the unreleased Schema Builder core/driver line. Set compatible
  published minimum versions before releasing; current workspace version
  constraints are not a claim that released Laconic 6.0.0 contains this API.
