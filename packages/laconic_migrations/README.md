# Laconic Migrations

Explicit database migrations for Laconic. This unreleased workspace package
requires the matching core and driver sources containing the Schema Builder API.
Its only runtime dependency is `laconic`; choose a driver in your application.

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_migrations/laconic_migrations.dart';

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

The first release provides a library API and an executable example. It does not
scan Dart files at runtime, generate migration files, or provide a global CLI,
automatic schema diff, or schema snapshots.

See [Schema Builder](../../SCHEMA.md) for the dialect support matrix and
[the example](example/laconic_migrations_example.dart) for a runnable workflow.

From the workspace root:

```sh
dart run packages/laconic_migrations/example/laconic_migrations_example.dart
```
