import 'package:laconic/laconic.dart';
import 'package:laconic_mariadb/laconic_mariadb.dart';
import 'package:test/test.dart';

void main() {
  final db = Laconic(
    MariadbDriver(const MariadbConfig(database: 'testdb', password: 'unused')),
  );
  test('MariaDB reuses MySQL bindings and JSON functions', () {
    final q = db
        .table('users')
        .whereJsonContains('payload->tags', 'a')
        .where('id', 3)
        .limit(2);
    expect(
      q.toSql(),
      'select * from users where json_contains(payload, ?, ?) and id = ? limit ?',
    );
    expect(q.getBindings(), ['"a"', r'$.tags', 3, 2]);
  });
  test('MariaDB rejects lateral joins before a connection is opened', () {
    expect(
      () => db.table('users').joinLateral(db.table('posts'), 'p').toSql(),
      throwsA(isA<LaconicException>()),
    );
  });
  test('grammar is shared between driver instances', () {
    final other = MariadbDriver(
      const MariadbConfig(database: 'other', password: 'unused'),
    );
    final first = MariadbDriver(
      const MariadbConfig(database: 'first', password: 'unused'),
    );
    expect(other.grammar, same(first.grammar));
  });
}
