# Laconic Migrations

Database migrations and the CLI are built into `laconic`. These unreleased APIs
require matching core and driver sources containing the Schema Builder API.
Import `Migration`, `MigrationStatus`, and `Migrator` from
`package:laconic/laconic.dart`. CLI APIs are exported separately from
`package:laconic/cli.dart` so the main library does not import CLI I/O.
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

// db is an existing Laconic instance using your chosen driver.
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
- `reset()`: reverse all recorded migrations. The history table remains.

The history table defaults to `migrations`; pass `table:` to override it.
Rollback checks that every selected migration definition exists before executing
the first `down()`.

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
operations. Migration functions execute application code; run trusted sources.

## CLI

Run the CLI from your application directory after resolving dependencies with
`dart pub get`. Add `laconic` and your selected driver to
that application's dependencies.

Create `database/migrations.dart` with a top-level `createDatabase()` function
returning `Laconic` or `Future<Laconic>`. For example, with SQLite:

```dart
import 'dart:io';
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

Laconic createDatabase() => Laconic(SqliteDriver(SqliteConfig(
  Platform.environment['DATABASE_PATH'] ?? 'app.db',
)));
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

# Give every pending migration its own batch.
dart run laconic migrate --step

# Generate an arbitrary change with up/down stubs to fill in.
dart run laconic make add_user_preferences
```

`make:migration`, `migrate:rollback`, and `migrate:status` are aliases. Use `--help`
on the CLI or a command for details. Plain stubs throw `UnimplementedError` until
filled in, so unfinished work is never silently recorded as successful.

Global options go before the command:

```sh
dart run laconic \
  --config tool/database.dart \
  --path database/changes \
  --table app_migrations \
  status --json
```

| Option | Default | Meaning |
|---|---|---|
| `--config` | `database/migrations.dart` | Dart file exporting `createDatabase()` |
| `--path` | `database/migrations` | Flat directory containing migration Dart files |
| `--table` | `migrations` | Database migration history table |

Paths are relative to the working directory; absolute paths are also supported.
The generator creates the migrations directory when needed. Execution commands
report a missing directory instead of silently running an empty registry.

Generated filenames use a UTC timestamp with microsecond precision followed by
the lower_snake_case name. Existing files are never overwritten. Each migration
file must export a top-level `Migration migration()` factory, and its migration
name must match the filename without `.dart`. To use an existing class through
the CLI, add a factory such as `Migration migration() => CreateUsers();` and
ensure its stable name matches its filename. Helpers should live outside the
migrations directory. Only regular `.dart` files in that directory are loaded;
subdirectories are not scanned and symlinked Dart files are rejected explicitly.

The launcher discovers files, generates a temporary entrypoint with normal Dart
imports under `.dart_tool/laconic/`, then invokes the Dart SDK. It
removes the entrypoint after the subprocess finishes, including failures. This
does not use reflection or interpret Dart source. The CLI requires the Dart SDK
even when the launcher itself is compiled to a native executable. A custom
statically registered executable can instead call `runMigrationCommand()` from
`package:laconic/cli.dart` directly; see its API documentation.

`status --json` writes an array of `{name, status, batch, missing}` to stdout.
Diagnostics go to stderr. Application configuration and query hooks should also
send their logs to stderr when machine-readable output is required. Successful
commands exit with 0; usage errors use 64, invalid migration data uses 65, missing
configuration uses 78, and migration failures use 70. Dart compilation failures
propagate the SDK's nonzero exit code.

Commands have no interactive confirmation and are suitable for deployment
scripts. `rollback` executes user-authored `down()` methods and can delete data.
The CLI does not add a cross-process lock: serialize execution in your deployment
system as described above. Automatic schema diff and schema snapshots are not
provided.

See [Schema Builder](../../SCHEMA.md) for the dialect support matrix and
[the example](../laconic_sqlite/example/migrations_example.dart) for a runnable workflow.

From the workspace root:

```sh
dart run packages/laconic_sqlite/example/migrations_example.dart
```
