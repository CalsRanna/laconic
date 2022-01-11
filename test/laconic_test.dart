import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

void main() {
  group('A group of tests', () {
    final database = Database(
      host: '127.0.0.1',
      port: 3333,
      database: 'mysql',
      username: 'root',
      password: 'root',
    );
    final table = 'user';

    setUp(() {
      // Additional setup goes here.
    });

    test('Get Test', () async {
      expect(await database.table(table).get(), isList);
    });

    test('First Test', () async {
      expect(await database.table(table).first(), isMap);
    });
  });
}
