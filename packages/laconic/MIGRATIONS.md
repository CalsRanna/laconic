# Laconic Migrations

Database migrations and the CLI are built into `laconic`. These unreleased APIs
require matching core and driver sources containing the Schema Builder API.
Import `Migration`, `MigrationStatus`, `Migrator`, and `MigrationCli` from `package:laconic/laconic.dart`.
The core uses `args`, `cli_util`, `io`, and `path` for the CLI, and has no
concrete database driver dependencies, including development dependencies.
Applications choose and inject their driver; integration tests live in driver packages.

```dart
import 'package:laconic/laconic.dart';

class CreateUsers extends Migration {
  @override
  String get name => '202610290001_create_users';

  @override
  Future<void> up(Laconic db) => db.schema.create('users', (table) {
    table.id();
    table.string('email');
    table.unique(['email']);
    table.timestamps();
  });

  @override
  Future<void> down(Laconic db) => db.schema.drop('users');
}

// Inside an async method; db is an existing Laconic instance using your driver.
final migrator = Migrator(db, migrations: [CreateUsers()]);
await migrator.migrate();
final states = await migrator.status();
await migrator.rollback();
```

Register migrations using normal Dart imports. Names are stable ASCII letters,
digits, and underscores, up to 255 characters. Use timestamp prefixes so lexical
ordering matches the intended order. Applied migrations must not be renamed or
edited. Keep every definition required to reverse your database history.
Names differing only by letter case are rejected, including on databases whose
default string collation is case-sensitive.

## Operations

- `migrate()`: run pending migrations in name order as one batch.
- `migrate(step: true)`: give each migration its own batch.
- `status()`: inspect pending/applied migrations, including missing definitions;
  this does not create or modify the history table.
- `rollback()`: reverse the most recent batch, in reverse execution order.
- `rollback(steps: n)`: reverse the latest n recorded migrations across batches.
- `rollback(batch: n)`: reverse exactly that batch; mutually exclusive with steps.
- `reset()`: reverse all recorded migrations. The history table remains.
- `refresh(steps: n)`: reverse the latest n migrations (all when omitted), then
  run all pending migrations, including previously pending definitions.
- `fresh(step: true)`: drop all tables in the history table's schema and migrate;
  `step` is optional and defaults to false. This also removes untracked tables.
- `migrate`, `rollback`, and `reset` accept `pretend: true` and an `onQuery`
  callback for SQL previews. See the limitations below.

`onApplied` and `onRolledBack` callbacks report each completed migration before
the next one starts. The CLI uses these to preserve progress output on failures.
`fresh` also has `onDropped`, called after the table wipe succeeds.

The history table defaults to `migrations`; pass `table:` to override it.
Rollback checks that every selected migration definition exists before executing
the first `down()`.
Refresh stops if any rollback fails. Refresh/fresh hold the instance's operation
guard across both phases, but do not wrap the whole workflow in one transaction.

## Failure and transaction behavior

SQLite, PostgreSQL, and SQL Server wrap each ordinary migration and its history
update in one transaction. Override `withinTransaction => false` for statements
that cannot run in a transaction. MySQL and MariaDB run without an automatic DDL
transaction because DDL can implicitly commit.

A failed `up()` is not recorded and stops the run. A failed `down()` keeps its
history record. On non-transactional engines, changes already made may remain;
inspect and repair them before retrying. A later migration's failure does not
undo earlier successful migrations. Reversing DDL does not restore deleted data.

Use `isolated: true` (CLI `--isolated`) to serialize cooperating deployments.
The instance also rejects overlapping mutations. Take a database backup before
destructive operations. Migration methods execute application code; run trusted sources.

## Conditions and named connections

Override `FutureOr<bool> shouldRun(Laconic database)` to decide whether a pending
migration should run. The argument is its resolved target connection. Returning
false leaves the migration pending and does not consume a step batch; `onSkipped`
reports it. A later run evaluates the condition again. Rollback always calls
`down()` for applied migrations, regardless of the condition. Previews skip the
condition and capture `up()` SQL, as in Laravel.

Override `String? get connection => 'reporting'` on a migration and supply
`Migrator(..., resolveConnection: (name) => connections[name]!)`. The resolver is
cached per name; the caller owns these connections and must close them. History
stays on the migrator's default connection. Same-connection transactional DDL and
history remain atomic. For a different connection, the target transaction commits
before default-connection history is updated; these cannot be one atomic
transaction. If history recording fails, inspect the target before retrying.
Rollback resolves every selected connection before executing the first `down()`.

CLI configurations can add an optional positional name:

```dart
static Future<Laconic> createDatabase([String? name]) async {
  // Resolve name, or return your default connection when null.
  return openApplicationDatabase(name);
}
```

Existing no-argument configurations remain valid. Use
`dart run laconic migrate --database=reporting` to select the default/history
connection for that run. The CLI caches each named connection and closes every
opened connection on success or failure. `MigrationCli.runCommand` accepts an
explicit `resolveConnection:` callback for statically registered applications.

## Migration isolation

All mutating `Migrator` methods accept `isolated: true`. The lock is nonblocking
and spans the entire operation, including refresh/fresh phases. `dumpSchema`
locks by default and holds the lock through its `onDumped` callback. Lock
contention throws `MigrationLockException` in the API; the CLI reports a skipped
operation and exits 0. Other connection, permission and migration errors still
fail. Every competing deployment must opt in; ordinary queries and unisolated
migrations do not honor this lock.

MySQL/MariaDB use `GET_LOCK`, PostgreSQL uses an advisory lock, and SQL Server
uses a session application lock. Scope is the default/history database, across
all history tables. Work on that connection stays pinned to the lock-owning
session, including each migration transaction. Named target databases are not
separately locked: deployments sharing targets must share a history database.
Locks release when the callback finishes or fails, or the server session ends.
Ordinary nested transactions remain unsupported; acquire isolation outside a
transaction.

SQLite uses a persistent `<canonical-db-path>.laconic-migrations.lock` SQLite
sidecar with an exclusive SQLite transaction. This coordinates connections,
isolates and processes using the same physical file and a filesystem supporting
SQLite locks. Do not delete the sidecar while deployments may run. In-memory
SQLite isolation only applies to that driver instance. All server deployments
must connect to the same server/database for the lock to coordinate them.

## Schema baselines

```sh
# Save schema plus applied migration names/batches, excluding business rows.
dart run laconic schema:dump
# Also remove only applied migration source files after the dump is saved.
dart run laconic schema:dump --prune
# A connection-specific baseline, or an explicit SQL path.
dart run laconic schema:dump --database=reporting
dart run laconic migrate --schema-path=database/schema/custom.sql --isolated
```

The project CLI defaults to `database/schema/default-schema.sql`, or
`database/schema/<connection>-schema.sql` with `--database`. `--schema-path`
overrides that path. The core API is explicit: configure
`Migrator(db, migrations: [...], schemaPath: path)` and call
`await migrator.dumpSchema(path)`. A custom `MigrationCli.runCommand` must also
provide `schemaPath:` or `--schema-path` for dumping; pruning additionally
requires a name-to-source-path `migrationFiles:` map.

When no migrations are recorded and the configured SQL file exists, `migrate`
loads the baseline, restores its history, then runs only remaining migrations.
It verifies the format's dialect/history-table metadata before import. Existing
business tables or views block loading; an empty history table may be replaced.
`fresh` can load a baseline after its explicit table wipe, but its existing
schema-scoped behavior is unchanged: views/external dependencies remain and must
be handled explicitly. `onSchemaLoaded` reports the successful import.
`--pretend` emits baseline SQL and pending migration SQL without importing it;
subsequent inspection still sees the real database, not the previewed baseline.

| Driver | Required native clients | Scope |
|---|---|---|
| MySQL | `mysqldump`, `mysql` | Configured database |
| MariaDB | `mariadb-dump`, `mariadb` | Configured database |
| PostgreSQL | `pg_dump`, `psql` | History table's schema, or current schema |
| SQLite | `sqlite3` (3.37+) | Ordinary file's `main` database |
| SQL Server | Unsupported | Explicit `LaconicException` |

Install clients compatible with the server and schema features. In particular,
`pg_dump` must not be older than the server, and `psql` must understand the dump's
commands. SQLite's native CLI must support the features in the linked SQLite
library; memory databases and attached-schema exports are unsupported. Native
clients run without a shell; passwords are passed through environment variables.
A `SchemaProcessRunner` override can select containerized clients or executable
paths. MySQL/MariaDB native clients cannot reuse a Dart `SecurityContext` or an in-memory pinned RSA key; these
configurations fail explicitly instead of silently dropping their trust settings.
Dump files are trusted executable SQL, including native views, triggers and other
schema objects. They contain schema only plus migration history, never business
rows. Cross-connection migration histories cannot be represented by one baseline
and are rejected while their definitions are available. PostgreSQL extensions and
objects in other schemas must already be available if referenced. Native
schema-qualified names are preserved, not renamed to a different target schema.

Dump output is written to a sibling temporary directory and replaces the prior
file only after successful export. `--prune` then deletes applied sources while
the same lock remains held; pending/conditionally skipped files remain. A failed
export preserves both the old dump and source files. If source deletion fails,
the saved baseline remains usable. Pruned entries appear as `BASELINE` in status;
JSON adds `baseline: true` only for those entries. Missing definitions absent from
the baseline remain `MISSING`. Pruning intentionally removes the ability to
reverse those old migrations: rollback/reset/refresh fail before any selected
`down()` when required definitions are absent. Keep the baseline in source control.

Native import on MySQL/MariaDB can leave partial DDL on failure. SQLite import is
transactional and PostgreSQL uses `psql --single-transaction`; an existing empty
history table is removed before invoking the native client. Baseline loading does
not reconstruct business rows or simulate data migrations that were pruned.

## CLI

Run the CLI from your application directory after resolving dependencies with
`dart pub get`. Add `laconic` and your selected driver to
that application's dependencies.

Create `database/migrations.dart` with a `DatabaseConfiguration` class whose static
`createDatabase()` method returns `Laconic` or `Future<Laconic>`. For example, with SQLite:

```dart
import 'dart:io';
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

abstract final class DatabaseConfiguration {
  static Laconic createDatabase() => Laconic(SqliteDriver(SqliteConfig(
    Platform.environment['DATABASE_PATH'] ?? 'app.db',
  )));
}
```

The configuration belongs to the application. Use any Laconic driver and read
connection credentials from your application's environment or configuration.
The CLI creates the connection only for execution/status commands and always
closes all opened connections afterward; generation and help do not load database configuration.

```sh
# Generate a create-table migration with a matching drop-table rollback.
dart run laconic make create_users --create=users

# Edit the generated file to define the remaining columns, then run it.
dart run laconic migrate

# Show pending/applied migrations and their batch numbers.
dart run laconic status
dart run laconic status --json

# Roll back the latest batch, or the latest two individual migrations.
dart run laconic rollback
dart run laconic rollback --step=2
dart run laconic rollback --batch=3

# Reverse all migrations, or reverse and run them again.
dart run laconic reset
dart run laconic refresh
dart run laconic refresh --step=2

# Delete all tables in the history schema (including untracked tables), then migrate.
dart run laconic fresh
dart run laconic fresh --step

# Preview migration SQL and bound values without executing that SQL.
dart run laconic migrate --pretend
dart run laconic rollback --pretend
dart run laconic reset --pretend

# Give every pending migration its own batch.
dart run laconic migrate --step

# Generate an arbitrary change with up/down stubs to fill in.
dart run laconic make add_user_preferences

# Generate up/down table-alteration stubs (both must be filled in).
dart run laconic make add_user_preferences --table=users
```

`make:migration` and `migrate:{rollback,status,reset,refresh,fresh}` are aliases. Use `--help`
on the CLI or a command for details. Plain stubs throw `UnimplementedError` until
filled in, so unfinished work is never silently recorded as successful.

Project options can go before or after database commands. A command-local value
overrides a global one. The generator also accepts a local `--path`:

```sh
dart run laconic \
  --config tool/database.dart \
  --path database/changes \
  --table app_migrations \
  status --json

dart run laconic status --path=database/changes --table=app_migrations --json
```

| Option | Default | Meaning |
|---|---|---|
| `--config` | `database/migrations.dart` | Dart file exporting `DatabaseConfiguration.createDatabase()` |
| `--path` | `database/migrations` | Flat directory containing migration Dart files |
| `--table` | `migrations` | Database migration history table |

Paths are relative to the working directory; absolute paths are also supported.
For `make`, local `--table` selects the table to alter; the global `--table`
still names migration history. `make --create` and `make --table` are mutually
exclusive. Explicit names are used; table names are not inferred from filenames.
The generator creates the migrations directory when needed. Execution commands
report a missing directory instead of silently running an empty registry.

Generated filenames use a UTC timestamp with microsecond precision followed by
the lower_snake_case name. Existing files are never overwritten. Each migration
file must export a `DatabaseMigration extends Migration` class with an unnamed,
zero-argument constructor. Its migration name must match the filename without
`.dart`. To use an existing class through the CLI, rename it to `DatabaseMigration`
or add `class DatabaseMigration extends CreateUsers {}` in its migration file.
Ensure its stable name matches its filename. Helpers should live outside the
migrations directory. Only regular `.dart` files in that directory are loaded;
subdirectories are not scanned and symlinked Dart files are rejected explicitly.

The launcher discovers files, generates a temporary entrypoint with normal Dart
imports under `.dart_tool/laconic/`, then invokes the Dart SDK. It
removes the entrypoint after the subprocess finishes, including failures. This
does not use reflection or interpret Dart source. The CLI requires the Dart SDK
even when the launcher itself is compiled to a native executable. A custom
statically registered executable can instead call `MigrationCli.runCommand()` from
`package:laconic/laconic.dart` directly; see its API documentation.

`status --json` writes an array of `{name, status, batch, missing}` to stdout.
Diagnostics go to stderr. Application configuration and query hooks should also
send their logs to stderr when machine-readable output is required. Successful
commands exit with 0; usage errors use 64, invalid migration data uses 65, missing
configuration uses 78, and migration failures use 70. Dart compilation failures
propagate the SDK's nonzero exit code.

### Production and destructive operations

Commands have no interactive confirmation. When `APP_ENV=production`, `migrate`,
`rollback`, `reset`, `refresh`, `fresh`, and `schema:dump --prune` require `--force`; refusal returns 78
before calling the configuration factory. `status`, help, and `--pretend` do not
require force. Applications using `runCommand` can supply `environment:` instead
of reading `APP_ENV`. Environment detection does not inspect database credentials.

```sh
APP_ENV=production dart run laconic migrate --force
```

`rollback`, `reset`, and `refresh` execute user-authored `down()` methods and can
delete data. `fresh` uses `SchemaBuilder.dropAllTables()` without calling `down()`.
It wipes the schema containing the configured history table: `main` on SQLite,
the selected database on MySQL/MariaDB, and the default schema on PostgreSQL/SQL
Server unless history is schema-qualified. Other schemas are preserved. Migrations
must target that schema themselves; `--table=app.history` does not rewrite their SQL.
Views and other external dependencies remain and may block drops; remove them
explicitly when necessary. The CLI does not silently cascade into other schemas.

Foreign keys owned by the selected tables are dropped before the tables, so
cycles work on MySQL, MariaDB, PostgreSQL, and SQL Server. SQLite uses its reserved
schema transaction with foreign keys temporarily disabled and restored afterward,
including on failure. SQLite virtual tables are dropped before their shadow
tables. PostgreSQL/SQL Server/SQLite table wipes are transactional; MySQL/MariaDB
may leave partial changes if a drop fails. A successful wipe is not undone if a
later migration fails.

### SQL previews

`--pretend` is supported by `migrate`, `rollback`, and `reset`. It prints `SQL:`
and separate JSON `Bindings:` lines, then `Would migrate:` or `Would roll back:`.
It reads history and structure metadata, but never executes migration SQL or
creates/updates history. Even raw SQL sent via `select`/`selectStream`, write
methods, and transactions on the supplied connection is captured without execution.
Normal queries return no rows or zero IDs/counts, so data-dependent code can take
a different branch or fail. Configuration must still connect to a real database;
opening a new SQLite file can create that empty file.

Existing-table `change()` and SQLite rebuild previews use current structure
metadata. Earlier previewed DDL is not applied or simulated: a later alteration
of a newly previewed table can fail because the table does not exist. A preview
can therefore be incomplete and is not a guarantee that execution will succeed.
Migration methods still execute Dart code; external side effects or separately
opened connections are outside the preview. Use trusted migrations.

Seeding and automatic schema diff remain outside this API. Unknown options fail
with usage code 64. Project differences such as schema-scoped wipes, explicit
connection ownership and non-atomic cross-connection history remain intentional.
Command semantics are based on [Laravel's migration lifecycle](https://laravel.com/framework/docs/13.x/migrations#running-migrations),
with the schema-scoped wipe and preview limits described here.

See [Schema Builder](../../SCHEMA.md) for the dialect support matrix and
[the example](../laconic_sqlite/example/migrations_example.dart) for a runnable workflow.

From the workspace root:

```sh
dart run packages/laconic_sqlite/example/migrations_example.dart
```
