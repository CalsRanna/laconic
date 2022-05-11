import 'package:laconic/laconic.dart';

void main() async {
  final db = DB(
    host: '127.0.0.1',
    port: 3333,
    database: 'foxy',
    username: 'root',
    password: 'root',
  );
  final table = 'example_table';
  try {
    await db.table(table).insert({'id': 1});
    await db.table(table).where('id', 1).sole();
    await db.table(table).where('id', 1).update({'name': 'laconic'});
    await db.table(table).where('id', 1).delete();
    await db.table(table).batchInsert([
      {'id': 1},
      {'id': 2},
      {'id': 3}
    ]);
  } catch (e) {
    // error handling code goes here
  }
}
