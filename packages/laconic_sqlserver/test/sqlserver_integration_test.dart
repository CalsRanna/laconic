import 'dart:typed_data';

import 'package:laconic/laconic.dart';
import 'package:laconic_sqlserver/laconic_sqlserver.dart';
import 'package:test/test.dart';
import 'test_helper.dart';

void main() {
  late Laconic db;
  const table = 'laconic_sqlserver_features';
  QueryBuilder query() => db.table(table);
  setUpAll(() async {
    await prepareDatabase();
    db = createDatabase(maxConnections: 1);
  });
  setUp(() async {
    await db.statement('drop table if exists $table');
    await db.statement('''create table $table (
      id int primary key, grp int, label nvarchar(100),
      payload nvarchar(max), created_at datetime2
    )''');
    await query().insert([
      {
        'id': 1,
        'grp': 1,
        'label': 'one',
        'payload': '{"tags":["a",1,true,null],"empty":null}',
        'created_at': DateTime(2026, 10, 29, 12, 30),
      },
      {
        'id': 2,
        'grp': 1,
        'label': 'two',
        'payload': '{"tags":["b",9007199254740992]}',
        'created_at': DateTime(2025, 5, 1),
      },
      {
        'id': 3,
        'grp': 2,
        'label': 'three',
        'payload': '{}',
        'created_at': null,
      },
    ]);
  });
  tearDownAll(() async {
    try {
      await db.statement('drop table if exists $table');
    } finally {
      await db.close();
    }
  });

  test(
    'APPLY executes correlated subqueries and preserves empty outer rows',
    () async {
      final subquery = db
          .table('$table c')
          .select(['c.label'])
          .whereColumn('c.grp', 'p.id')
          .orderByDesc('c.id')
          .limit(1);
      final inner = db
          .table('$table p')
          .select(['p.id', 'selected.label'])
          .joinLateral(subquery, 'selected')
          .orderBy('p.id');
      expect((await inner.get()).map((r) => r.toMap()), [
        {'id': 1, 'label': 'two'},
        {'id': 2, 'label': 'three'},
      ]);
      final outer = db
          .table('$table p')
          .select(['p.id', 'selected.label'])
          .leftJoinLateral(subquery, 'selected')
          .orderBy('p.id');
      expect((await outer.get()).last['label'], isNull);
    },
  );

  test('date extraction and lexicographic tuple comparisons execute', () async {
    expect(await query().whereDate('created_at', '2026-10-29').pluck('id'), [
      1,
    ]);
    expect(await query().whereTime('created_at', '12:30:00').pluck('id'), [1]);
    expect(await query().whereYear('created_at', 2025).pluck('id'), [2]);
    expect(
      await query()
          .whereRowValues(['grp', 'id'], '>', [1, 1])
          .orderBy('id')
          .pluck('id'),
      [2, 3],
    );
    expect(await query().groupLimit(1, 'grp').count(), 2);
  });

  test(
    'bound values preserve binary, Unicode, NULL and 64-bit integers',
    () async {
      final bytes = Uint8List.fromList([0, 1, 127, 255]);
      final row =
          (await db.select(
            'select ? as big, ? as bytes, ? as text_value, cast(? as int) as missing',
            [9007199254740993, bytes, "测试 ? '; drop table $table; --", null],
          )).single;
      expect(row['big'], 9007199254740993);
      expect(row['bytes'], bytes);
      expect(row['text_value'], "测试 ? '; drop table $table; --");
      expect(row['missing'], isNull);
      expect(await query().count(), 3);
      final streamRow = await query().where('id', 1).cursor().first;
      streamRow.values[0] = 99;
      expect(streamRow['id'], 99);
    },
  );

  test(
    'JSON membership distinguishes types, case and adjacent large integers',
    () async {
      expect(
        await query()
            .whereJsonContains('payload->tags', ['a', 1, true, null])
            .pluck('id'),
        [1],
      );
      expect(await query().whereJsonContains('payload->tags', '1').count(), 0);
      expect(await query().whereJsonContains('payload->tags', 'A').count(), 0);
      expect(
        await query().whereJsonContains('payload->tags', 1.0).pluck('id'),
        [1],
      );
      expect(
        await query()
            .whereJsonContains('payload->tags', 9007199254740993)
            .count(),
        0,
      );
      await query().where('id', 2).update({'payload': '{"tags":["a "]}'});
      expect(
        await query()
            .where('id', 2)
            .whereJsonContains('payload->tags', 'a')
            .count(),
        0,
      );
      expect(await query().whereJsonContainsKey('payload->empty').pluck('id'), [
        1,
      ]);
      expect(await query().whereJsonLength('payload->missing', 0).count(), 0);
    },
  );

  test(
    'lock hints execute inside transactions and empty-update upserts retain data',
    () async {
      await db.transaction(() async {
        expect((await query().where('id', 1).lockForUpdate().first())['id'], 1);
        expect((await query().where('id', 2).sharedLock().first())['id'], 2);
      });
      await query().upsert(
        [
          {'id': 1, 'label': 'changed'},
          {'id': 4, 'label': 'four'},
        ],
        uniqueBy: ['id'],
        update: [],
      );
      expect(await query().where('id', 1).value('label'), 'one');
      expect(await query().where('id', 4).value('label'), 'four');
    },
  );

  test(
    'TLS connects with an explicit development certificate opt-in',
    () async {
      final settings = testConfig();
      final encrypted = Laconic(
        SqlserverDriver(
          SqlserverConfig(
            host: settings.host,
            port: settings.port,
            database: settings.database,
            username: settings.username,
            password: settings.password,
            allowBadCertificates: true,
          ),
        ),
      );
      try {
        expect(
          (await encrypted.select('select ? as value', [42])).single['value'],
          42,
        );
      } finally {
        await encrypted.close();
      }
    },
  );
}
