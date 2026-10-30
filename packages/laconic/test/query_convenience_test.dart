import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

import 'support/mock_database.dart';

void main() {
  late MockDriver driver;
  late Laconic db;
  setUp(() {
    driver =
        MockDriver()
          ..mockResults = [
            {'id': 5},
            {'id': 4},
          ];
    db = Laconic(driver);
  });

  test(
    'descending cancellation and false callbacks never fetch another chunk',
    () async {
      expect(
        await db.table('items').chunkByIdDesc(2, (_) async => false),
        isFalse,
      );
      expect(driver.executedSql, hasLength(1));
      expect(driver.executedSql.single, contains('order by id desc'));
      driver.executedSql.clear();
      expect(
        await db
            .table('items')
            .lazyByIdDesc(2)
            .take(1)
            .map((r) => r['id'])
            .toList(),
        [5],
      );
      expect(driver.executedSql, hasLength(1));
      driver.executedSql.clear();
      await expectLater(
        db
            .table('items')
            .chunkByIdDesc(2, (_) async => throw StateError('stop')),
        throwsStateError,
      );
      expect(driver.executedSql, hasLength(1));
      driver.executedSql.clear();
      expect(
        await db
            .table('items')
            .limit(0)
            .chunkByIdDesc(2, (_) => fail('not called')),
        isTrue,
      );
      expect(driver.executedSql, isEmpty);
    },
  );

  test(
    'chunkMap awaits callbacks sequentially and stops issuing queries on failure',
    () async {
      final visits = <int>[];
      var active = 0;
      final mapped = await db
          .table('items')
          .orderByDesc('id')
          .limit(2)
          .chunkMap<int>((row) async {
            active++;
            expect(active, 1);
            await Future<void>.delayed(Duration.zero);
            visits.add(row['id'] as int);
            active--;
            return row['id'] as int;
          }, count: 2);
      expect(mapped, [5, 4]);
      expect(visits, [5, 4]);
      expect(driver.executedSql, hasLength(1));
      driver.executedSql.clear();
      await expectLater(
        db
            .table('items')
            .orderBy('id')
            .chunkMap<int>((_) async => throw StateError('mapper'), count: 2),
        throwsStateError,
      );
      expect(driver.executedSql, hasLength(1));
    },
  );

  test(
    'relative dates freeze the reference time at construction and clone it',
    () {
      final now = DateTime.utc(2026, 10, 30, 12, 34, 56, 987, 654);
      final q = db.table('items').wherePast(['due_at', 'review_at'], now: now);
      expect(q.getBindings(), ['2026-10-30 12:34:56', '2026-10-30 12:34:56']);
      final copy = q.clone().whereNowOrFuture(
        'updated_at',
        now: DateTime.utc(2026, 10, 31),
      );
      expect(q.getBindings(), ['2026-10-30 12:34:56', '2026-10-30 12:34:56']);
      expect(copy.getBindings().last, '2026-10-31 00:00:00');
      expect(driver.executedSql, isEmpty);
    },
  );

  test(
    'tap and pipe receive this query exactly once without implicit execution',
    () {
      final q = db.table('items');
      var calls = 0;
      void inspect(QueryBuilder query) {
        expect(query, same(q));
        calls++;
      }

      expect(q.tap(inspect), same(q));
      expect(q.pipe(inspect), same(q));
      expect(q.pipe((_) => <String>[]), isA<List<String>>());
      expect(calls, 2);
      expect(driver.executedSql, isEmpty);
    },
  );
}
