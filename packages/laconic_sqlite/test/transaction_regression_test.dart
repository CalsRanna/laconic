import 'dart:async';
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Laconic db;
  setUp(() async {
    db = Laconic(SqliteDriver(SqliteConfig(':memory:')));
    await db.statement('CREATE TABLE entries (id INTEGER PRIMARY KEY)');
  });
  tearDown(() => db.close());

  test(
    'overlapping transactions wait and do not roll back each other',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final first = db.transaction(() async {
        await db.table('entries').insert([
          {'id': 1},
        ]);
        entered.complete();
        await release.future;
        await db.table('entries').insert([
          {'id': 2},
        ]);
      });
      await entered.future;
      var secondEntered = false;
      final second = db.transaction(() async {
        secondEntered = true;
        await db.table('entries').insert([
          {'id': 3},
        ]);
      });
      await Future<void>.delayed(Duration.zero);
      expect(secondEntered, isFalse);
      release.complete();
      await Future.wait([first, second]);
      expect(await db.table('entries').orderBy('id').pluck('id'), [1, 2, 3]);
    },
  );

  test(
    'an unrelated write waits and survives a transaction rollback',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final first = db.transaction(() async {
        await db.table('entries').insert([
          {'id': 1},
        ]);
        entered.complete();
        await release.future;
        throw StateError('rollback');
      });
      final failed = expectLater(first, throwsA(isA<LaconicException>()));
      await entered.future;
      var writeFinished = false;
      final write = db
          .table('entries')
          .insert([
            {'id': 2},
          ])
          .then((_) {
            writeFinished = true;
          });
      await Future<void>.delayed(Duration.zero);
      expect(writeFinished, isFalse);
      release.complete();
      await failed;
      await write;
      expect(await db.table('entries').pluck('id'), [2]);
    },
  );

  test(
    'nested transaction rejection leaves outer transaction usable',
    () async {
      await db.transaction(() async {
        await db.table('entries').insert([
          {'id': 1},
        ]);
        await expectLater(
          db.transaction(() async {}),
          throwsA(isA<LaconicException>()),
        );
        await db.table('entries').insert([
          {'id': 2},
        ]);
      });
      expect(await db.table('entries').count(), 2);
    },
  );

  test(
    'work scheduled from an expired transaction cannot enter a later one',
    () async {
      final run = Completer<void>();
      late Future<void> lateWrite;
      await db.transaction(() async {
        lateWrite = run.future.then(
          (_) => db.statement('INSERT INTO entries VALUES (1)'),
        );
      });
      final rejected = expectLater(lateWrite, throwsA(isA<LaconicException>()));
      run.complete();
      await rejected;
      expect(await db.table('entries').count(), 0);
    },
  );
}
