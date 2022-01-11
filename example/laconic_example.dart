import 'dart:io';
import 'package:laconic/laconic.dart';
import 'package:logging/logging.dart';

void main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print(
        '[${record.time}][${record.loggerName}][${record.level}]: ${record.message}');
  });
  final logger = Logger('Laconic');

  final database = Database(
    host: '127.0.0.1',
    port: 3333,
    database: 'foxy',
    username: 'root',
    password: 'root',
  );
  final table = 'dbc_spell_icon';
  try {
    var affectedRows = await database.table(table).insert({'ID': 10000});
    logger.info(affectedRows);
    var row = await database.table(table).where('ID', 10000).sole();
    logger.info(row);
    affectedRows = await database
        .table(table)
        .where('ID', 10000)
        .update({'TextureFileName': 'Test'});
    logger.info(affectedRows);
    affectedRows = await database.table(table).where('ID', 10000).delete();
    logger.info(affectedRows);
    affectedRows = await database.table(table).batchInsert([
      {'ID': 10001},
      {'ID': 10002},
      {'ID': 10003}
    ]);
    logger.info(affectedRows);
  } catch (e) {
    print(e);
  }
  exit(0);
}
