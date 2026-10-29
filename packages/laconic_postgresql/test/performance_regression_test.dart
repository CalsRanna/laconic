import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';
import 'package:test/test.dart';

void main() {
  Laconic database({String database = 'testdb'}) => Laconic(
    PostgresqlDriver(
      PostgresqlConfig(
        host: '127.0.0.1',
        port: 5433,
        database: database,
        username: 'postgres',
        password: 'postgres',
        useSsl: false,
      ),
    ),
  );

  test(
    'repeated queries reuse a server statement and eviction deallocates plans',
    () async {
      final db = database();
      addTearDown(db.close);
      const sql = r'SELECT $1::int AS laconic_repeat';
      final initialPid =
          (await db.select('SELECT pg_backend_pid() AS pid')).single['pid'];
      for (var i = 0; i < 120; i++) {
        expect((await db.select(sql, [i])).single['laconic_repeat'], i);
      }
      expect(
        (await db.select(
          r'SELECT COUNT(*)::int AS n FROM pg_prepared_statements WHERE statement = $1',
          [sql],
        )).single['n'],
        1,
      );
      for (var i = 0; i < 75; i++) {
        await db.select('SELECT $i AS laconic_unique');
      }
      expect(
        (await db.select(
          'SELECT COUNT(*)::int AS n FROM pg_prepared_statements',
        )).single['n'],
        lessThanOrEqualTo(50),
      );
      expect(
        (await db.select('SELECT pg_backend_pid() AS pid')).single['pid'],
        initialPid,
      );
    },
  );

  test(
    'transaction statement cache is shared concurrently then disposed',
    () async {
      final db = database();
      addTearDown(db.close);
      const sql = r'SELECT $1::int AS laconic_tx_value';
      await db.transaction(() async {
        final results = await Future.wait(
          List.generate(20, (i) => db.select(sql, [i])),
        );
        expect([
          for (final r in results) r.single['laconic_tx_value'],
        ], List.generate(20, (i) => i));
        expect(
          (await db.select(
            r'SELECT COUNT(*)::int AS n FROM pg_prepared_statements WHERE statement = $1',
            [sql],
          )).single['n'],
          1,
        );
        await expectLater(
          db.transaction(() async {}),
          throwsA(isA<LaconicException>()),
        );
        expect((await db.select('SELECT 1 AS ok')).single['ok'], 1);
      });
      expect(
        (await db.select(
          r'SELECT COUNT(*)::int AS n FROM pg_prepared_statements WHERE statement = $1',
          [sql],
        )).single['n'],
        0,
      );
    },
  );

  test('rollback and query errors release transaction statements', () async {
    final db = database();
    addTearDown(db.close);
    const sql = r'SELECT $1::int AS laconic_rollback_value';
    await expectLater(
      db.transaction(() async {
        await db.select(sql, [1]);
        await db.select('SELECT 1 / 0');
      }),
      throwsA(
        isA<LaconicException>().having((e) => e.code, 'SQLSTATE', '22012'),
      ),
    );
    expect(
      (await db.select(
        r'SELECT COUNT(*)::int AS n FROM pg_prepared_statements WHERE statement = $1',
        [sql],
      )).single['n'],
      0,
    );
    expect((await db.select('SELECT 1 AS ok')).single['ok'], 1);
  });

  test(
    'a second driver retains its database inside another driver transaction',
    () async {
      final a = database();
      final b = database(database: 'postgres');
      addTearDown(a.close);
      addTearDown(b.close);
      await a.transaction(() async {
        expect(
          (await b.select('SELECT current_database() AS db')).single['db'],
          'postgres',
        );
        await b.transaction(() async {
          expect(
            (await a.select('SELECT current_database() AS db')).single['db'],
            'testdb',
          );
        });
      });
    },
  );

  test(
    'real PostgreSQL accepts quoted, native, mixed and JSON placeholders',
    () async {
      final db = database();
      addTearDown(db.close);
      final row =
          (await db.select(
            r"SELECT '?' AS literal, $1::int AS a, ?::int AS b",
            [1, 2],
          )).single;
      expect(row.toMap(), {'literal': '?', 'a': 1, 'b': 2});
      expect(
        (await db.select('SELECT ?::jsonb ? ? AS found', [
          '{"key":1}',
          'key',
        ])).single['found'],
        isTrue,
      );
      expect(
        (await db.select(
          "SELECT '{}'::jsonb ? 'key' AS found",
        )).single['found'],
        isFalse,
      );
      final q = db.table('(SELECT 1 AS id) AS t').where('id', 1).whereRaw(
        r"id = $1 AND '?' = '?'",
        [1],
      );
      expect((await q.get()).single['id'], 1);
    },
  );
}
