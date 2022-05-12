import 'package:laconic/laconic.dart';

void main() async {
  final db = DB(
    host: '127.0.0.1',
    port: 33060,
    database: 'acore_world',
    username: 'root',
    password: 'root',
  );
  var builder = QueryBuilder.from(db: db, table: 'creature_template');
  builder = builder
      .where(column: 'entry', value: null)
      .where(column: 'name', comparator: 'like', value: null)
      .where(column: 'subname', comparator: 'like', value: null)
      .limit(10);

  // var creatures = <CreatureTemplate>[];
  // for (int i = 0; i < rows.length; i++) {
  //   creatures.add(CreatureTemplate.fromJson(rows[i]));
  // }
  print(builder.toSql());
  print(builder.get());
}
