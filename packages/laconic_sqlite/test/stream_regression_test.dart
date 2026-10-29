import 'dart:async';

import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Laconic db;
  setUp(() async {
    db = Laconic(SqliteDriver(SqliteConfig(':memory:')));
    await db.statement('CREATE TABLE entries (id INTEGER PRIMARY KEY)');
    await db.table('entries').insert([
      {'id': 1},
      {'id': 2},
      {'id': 3},
    ]);
  });
  tearDown(() => db.close());

  test('SQLite cursor stops executing when the consumer cancels', () async {
    const sql = 'SELECT ? AS value UNION ALL SELECT abs(-9223372036854775808)';
    for (final value in [1, 2]) {
      final rows = await db.selectStream(sql, [value]).take(1).toList();
      expect(rows.single['value'], value);
    }
    expect(await db.table('entries').count(), 3);
  });

  test(
    'SQLite cursor delivers earlier rows before a later SQL error',
    () async {
      const sql =
          'SELECT 1 AS value UNION ALL SELECT abs(-9223372036854775808)';
      await expectLater(
        db.selectStream(sql),
        emitsInOrder([
          isA<LaconicResult>().having((row) => row['value'], 'value', 1),
          emitsError(isA<LaconicException>()),
          emitsDone,
        ]),
      );
      await db.statement('DROP TABLE entries');
      expect((await db.select('SELECT 1 AS value')).single['value'], 1);
    },
  );

  test(
    'SQLite cursor cancellation releases the connection and statement',
    () async {
      final rows = StreamIterator(db.table('entries').orderBy('id').cursor());
      addTearDown(rows.cancel);
      expect(await rows.moveNext(), isTrue);
      var dropped = false;
      final drop = db
          .statement('DROP TABLE entries')
          .then((_) => dropped = true);
      await Future<void>.delayed(Duration.zero);
      expect(dropped, isFalse);
      await rows.cancel();
      await drop.timeout(const Duration(seconds: 2));
      expect(dropped, isTrue);
    },
  );

  test('SQLite cursor owns its statement during transaction queries', () async {
    const sql = 'SELECT id FROM entries ORDER BY id';
    final seen = <Object?>[];
    await db.transaction(() async {
      await for (final row in db.selectStream(sql)) {
        seen.add(row['id']);
        expect((await db.select(sql)).length, 3);
      }
    });
    expect(seen, [1, 2, 3]);
  });
}
