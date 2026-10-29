import 'dart:io';
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlserver/laconic_sqlserver.dart';

Future<void> main() async {
  final db = Laconic(
    SqlserverDriver(
      SqlserverConfig(
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
