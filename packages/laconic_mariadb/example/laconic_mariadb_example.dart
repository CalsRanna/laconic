import 'dart:io';
import 'package:laconic/laconic.dart';
import 'package:laconic_mariadb/laconic_mariadb.dart';

Future<void> main() async {
  final db = Laconic(
    MariadbDriver(
      MariadbConfig(
        host: Platform.environment['DB_HOST'] ?? '127.0.0.1',
        database: Platform.environment['DB_DATABASE'] ?? 'app',
        username: Platform.environment['DB_USER'] ?? 'app',
        password: Platform.environment['DB_PASSWORD'] ?? '',
      ),
    ),
  );
  try {
    final rows = await db.select('select ? as example_value', [42]);
    print(rows.single.toMap());
  } finally {
    await db.close();
  }
}
