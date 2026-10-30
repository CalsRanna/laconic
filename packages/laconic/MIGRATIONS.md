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

Run exactly one migrator per database at a time, using your deployment system to
serialize runs. The instance rejects overlapping mutations but does not provide
a cross-process/distributed lock. Take a database backup before destructive
operations. Migration methods execute application code; run trusted sources.

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
closes it afterward; generation and help do not load database configuration.

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
`rollback`, `reset`, `refresh`, and `fresh` require `--force`; refusal returns 78
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

The CLI does not add a cross-process lock: serialize execution in your deployment
system as described above. `--isolated`, seeding, schema dump/squashing, and
automatic schema diff are not provided. Unknown options fail with usage code 64.
Command semantics are based on [Laravel's migration lifecycle](https://laravel.com/framework/docs/13.x/migrations#running-migrations),
with the schema-scoped wipe and preview limits described here.

See [Schema Builder](../../SCHEMA.md) for the dialect support matrix and
[the example](../laconic_sqlite/example/migrations_example.dart) for a runnable workflow.

From the workspace root:

```sh
dart run packages/laconic_sqlite/example/migrations_example.dart
```
