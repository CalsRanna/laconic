import 'dart:async';

import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class DriverRegressions {
  /// Connection and write contracts shared by the MariaDB and SQL Server drivers.
  static void register({
    required Laconic Function({int maxConnections}) createDatabase,
    required String createTable,
    required String sessionQuery,
    required String driverName,
  }) {
    const table = 'laconic_driver_contract';
    late Laconic db;
    QueryBuilder query() => db.table(table);
    setUp(() async {
      db = createDatabase(maxConnections: 1);
      await db.statement('drop table if exists $table');
      await db.statement(createTable);
    });
    tearDown(() async {
      try {
        await db.statement('drop table if exists $table');
      } finally {
        await db.close();
      }
    });

    test('generated ID, Unicode, raw writes and affected row counts', () async {
      final id = await query().insertGetId({
        'name': "测试 O'Reilly ?",
        'score': 1.5,
      });
      expect(id, greaterThan(0));
      expect((await query().find(id))['name'], "测试 O'Reilly ?");
      expect(
        await query().where('id', id).update({
          'score': Expression('score + 2'),
        }),
        1,
      );
      expect(await query().where('id', id).value('score'), 3.5);
      expect(await query().where('id', id).increment('score', amount: 2), 1);
      expect(await query().where('id', id).delete(), 1);
      expect(await query().where('id', id).delete(), 0);
    });

    test('upsert updates selected columns and inserts new rows', () async {
      await query().insert([
        {'name': 'one', 'score': 1.5},
      ]);
      await query().upsert(
        [
          {'name': 'one', 'score': 2.5},
          {'name': 'two', 'score': 3.5},
        ],
        uniqueBy: ['name'],
        update: ['score'],
      );
      expect(await query().count(), 2);
      expect(await query().orderBy('name').pluck('score'), [2.5, 3.5]);
    });

    test(
      'commit and rollback preserve the original application error',
      () async {
        await db.transaction(
          () => query().insert([
            {'name': 'committed'},
          ]),
        );
        final original = LaconicException('application failure');
        await expectLater(
          db.transaction(() async {
            await query().insert([
              {'name': 'rolled back'},
            ]);
            throw original;
          }),
          throwsA(same(original)),
        );
        expect(await query().pluck('name'), ['committed']);
        expect(
          await query().insertGetId({'name': 'after rollback'}),
          greaterThan(0),
        );
      },
    );

    test(
      'concurrent transaction queries serialize on one connection',
      () async {
        await db.transaction(() async {
          await Future.wait([
            for (var i = 0; i < 5; i++)
              query().insert([
                {'name': 'row$i'},
              ]),
          ]);
          expect(await query().count(), 5);
          final sessions = await Future.wait([
            for (var i = 0; i < 3; i++) db.select(sessionQuery),
          ]);
          expect(
            sessions.map((rows) => rows.single.values.single).toSet(),
            hasLength(1),
          );
          await expectLater(
            db.transaction(() async {}),
            throwsA(isA<LaconicException>()),
          );
          expect(await query().count(), 5);
        });
      },
    );

    test(
      'query failures release pool slots and expose driver error metadata',
      () async {
        await query().insert([
          {'name': 'unique'},
        ]);
        for (var i = 0; i < 3; i++) {
          await expectLater(
            query().insert([
              {'name': 'unique'},
            ]),
            throwsA(
              isA<LaconicException>()
                  .having((e) => e.driver, 'driver', driverName)
                  .having((e) => e.code, 'code', isNotNull),
            ),
          );
        }
        expect(await query().count(), 1);
      },
    );

    test(
      'native cursor binds values and cancellation releases a pool slot',
      () async {
        await query().insert([
          for (var i = 0; i < 100; i++) {'name': 'row$i'},
        ]);
        final first =
            await query()
                .where('id', 0, comparator: '>')
                .orderBy('id')
                .cursor()
                .take(2)
                .toList();
        expect(first, hasLength(2));
        expect(await query().count(), 100);
        await db.transaction(() async {
          expect(await query().orderBy('id').cursor().take(1).length, 1);
          expect(await query().count(), 100);
          await query().where('id', first.first['id']).update({
            'name': 'after cursor',
          });
        });
      },
    );

    test('stream errors release pool slots', () async {
      await expectLater(
        db.selectStream('select * from laconic_missing_table').drain<void>(),
        throwsA(isA<LaconicException>()),
      );
      expect(await query().count(), 0);
    });

    test('transaction zones cannot be reused after completion', () async {
      final start = Completer<void>();
      late Future<void> escaped;
      await db.transaction(() async {
        escaped = () async {
          await start.future;
          await query().count();
        }();
      });
      final assertion = expectLater(escaped, throwsA(isA<LaconicException>()));
      start.complete();
      await assertion;
    });

    test('parallel transactions use different sessions', () async {
      final pool = createDatabase(maxConnections: 2);
      try {
        final entered = Completer<void>();
        final release = Completer<void>();
        final transaction = pool.transaction(() async {
          final rows = await pool.select(sessionQuery);
          entered.complete();
          await release.future;
          return rows.single.values.single;
        });
        await entered.future;
        try {
          final outside =
              (await pool.select(sessionQuery)).single.values.single;
          release.complete();
          expect(await transaction, isNot(outside));
        } finally {
          if (!release.isCompleted) release.complete();
          await transaction;
        }
      } finally {
        await pool.close();
      }
    });

    test('truncate resets identity generation', () async {
      await query().insertGetId({'name': 'before'});
      await query().truncate();
      expect(await query().count(), 0);
      expect(await query().insertGetId({'name': 'after'}), 1);
    });
  }
}
