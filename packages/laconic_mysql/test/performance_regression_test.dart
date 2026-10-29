import 'dart:async';
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
import 'package:laconic_mysql/src/client/connection/connection.dart';
import 'package:test/test.dart';

void main() {
  Laconic database({String database = 'testdb', bool tls = false}) => Laconic(
    MysqlDriver(
      MysqlConfig(
        host: '127.0.0.1',
        database: database,
        username: 'root',
        password: 'root',
        maxConnections: 1,
        useSsl: tls,
        allowBadCertificates: tls,
      ),
    ),
  );

  test(
    'concurrent commands on a single connection receive their own responses',
    () async {
      final connection = await MysqlConnection.createConnection(
        host: '127.0.0.1',
        port: 3306,
        databaseName: 'testdb',
        userName: 'root',
        password: 'root',
        secure: false,
        commandTimeout: const Duration(seconds: 2),
      );
      addTearDown(connection.close);
      await connection.connect();
      final text = await Future.wait([
        connection.execute('SELECT 101 AS marker, SLEEP(0.01)'),
        connection.execute('SELECT 202 AS marker'),
      ]);
      expect(
        [for (final r in text) r.rows.single.toMap()['marker']],
        ['101', '202'],
      );
      final statement = await connection.prepare(
        'SELECT ? AS marker, SLEEP(0.01)',
      );
      final prepared = await Future.wait([
        statement.execute([303]),
        statement.execute([404]),
      ]);
      expect(
        [for (final r in prepared) r.rows.single.toTypedMap()['marker']],
        [303, 404],
      );
      await statement.deallocate();
      final bad = connection.execute(
        'SELECT * FROM laconic_missing_regression_table',
      );
      final failure = expectLater(bad, throwsA(isA<Exception>()));
      final next = connection.execute('SELECT 505 AS marker');
      await failure;
      expect((await next).rows.single.toMap()['marker'], '505');
    },
  );

  test('queued command waits until a streaming result has drained', () async {
    final connection = await MysqlConnection.createConnection(
      host: '127.0.0.1',
      port: 3306,
      databaseName: 'testdb',
      userName: 'root',
      password: 'root',
      secure: false,
    );
    addTearDown(connection.close);
    await connection.connect();
    final stream = await connection.execute(
      'SELECT 1 AS marker UNION ALL SELECT 2',
      null,
      true,
    );
    final next = connection.execute('SELECT 3 AS marker');
    final streamed = await stream.rowStream.toList();
    expect([for (final row in streamed) row.toMap()['marker']], ['1', '2']);
    expect((await next).rows.single.toMap()['marker'], '3');
  });

  test(
    'transaction queries share the cache without racing preparation',
    () async {
      final db = database();
      addTearDown(db.close);
      await db.transaction(() async {
        final rows = await Future.wait(
          List.generate(
            10,
            (i) => db.select('SELECT ? AS marker, SLEEP(0.001)', [i]),
          ),
        );
        expect([
          for (final row in rows) row.single['marker'],
        ], List.generate(10, (i) => i));
        await expectLater(
          db.transaction(() async {}),
          throwsA(isA<LaconicException>()),
        );
        expect((await db.select('SELECT 1 AS marker')).single['marker'], 1);
      });
    },
  );

  test(
    'a second driver retains its database inside another driver transaction',
    () async {
      final a = database();
      final b = database(database: 'information_schema');
      addTearDown(a.close);
      addTearDown(b.close);
      await a.transaction(() async {
        expect(
          (await b.select('SELECT DATABASE() AS db')).single['db'],
          'information_schema',
        );
        await b.transaction(() async {
          expect(
            (await a.select('SELECT DATABASE() AS db')).single['db'],
            'testdb',
          );
        });
      });
    },
  );

  test('TLS can return 4 MiB within the default command timeout', () async {
    final db = database(tls: true);
    addTearDown(db.close);
    final rows = await db.select("SELECT REPEAT('x', ?) AS payload", [
      4 * 1024 * 1024,
    ]);
    expect((rows.single['payload'] as String).length, 4 * 1024 * 1024);
  });
}
