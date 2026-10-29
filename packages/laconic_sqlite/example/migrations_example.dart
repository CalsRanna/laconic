import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

class CreateUsers extends Migration {
  @override
  String get name => '202610290001_create_users';

  @override
  Future<void> up(Laconic database) => database.schema.create('users', (table) {
    table.id();
    table.string('email');
    table.unique(['email']);
    table.timestamps();
  });

  @override
  Future<void> down(Laconic database) => database.schema.drop('users');
}

Future<void> main() async {
  final db = Laconic(SqliteDriver(SqliteConfig(':memory:')));
  try {
    final migrator = Migrator(db, migrations: [CreateUsers()]);
    print('Applied: ${await migrator.migrate()}');
    await db.table('users').insert([
      {'email': 'ada@example.test'},
    ]);
    print('Columns: ${await db.schema.getColumnListing('users')}');
    print('Users: ${await db.table('users').count()}');
    for (final status in await migrator.status()) {
      print('${status.name}: batch ${status.batch}');
    }
    print('Rolled back: ${await migrator.rollback()}');
  } finally {
    await db.close();
  }
}
