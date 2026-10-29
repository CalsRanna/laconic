## 1.0.0 (Unreleased)

- Add the `laconic_migrations` executable with `make`, `migrate`, `rollback`, and
  `status`, Laravel-style aliases, batch/step options, and JSON status output.
- Generate timestamped migration factories, optionally with create/drop-table
  bodies, without overwriting existing files.
- Load application-owned database configuration and migration factories through
  temporary static Dart entrypoints. Forward diagnostics and exit codes, close
  database connections, and remove temporary files after execution.
- Add an embeddable `runMigrationCommand` CLI API and test native launcher SDK
  discovery, failure behavior, generated files, and end-to-end SQLite workflows.
- Add explicit `Migration` registration and `Migrator` execution using Laconic.
- Track successful migrations and batches; support status, rollback, and reset.
- Wrap each migration and history update in a transaction when supported, with
  per-migration opt-out. Preserve records when rollback fails.
- Preflight missing rollback definitions and reject overlapping instance runs.
- Validate the workflow against SQLite, MySQL, MariaDB, PostgreSQL, and SQL Server.
- Requires the unreleased Schema Builder core/driver line. Set compatible
  published minimum versions before releasing; current workspace version
  constraints are not a claim that released Laconic 6.0.0 contains this API.
