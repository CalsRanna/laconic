import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
import 'package:test/test.dart';

/// Regression tests for the MySQL connection-pool slot leak.
///
/// A connection must be returned when the callback throws. Otherwise, after
/// maxConnections failures the pool hangs on the next acquire. The pool uses
/// try/finally so slots are always returned.
void main() {
  group('MySQL connection pool leak regression:', () {
    const maxConnections = 2;

    late Laconic laconic;

    setUp(() {
      laconic = Laconic(
        MysqlDriver(
          MysqlConfig(
            database: 'testdb',
            host: '127.0.0.1',
            port: 3306,
            username: 'root',
            password: 'root',
            maxConnections: maxConnections,
            useSsl: false,
          ),
        ),
      );
    });

    tearDown(() async {
      await laconic.close();
    });

    test(
      'connection pool returns slots after query errors',
      () async {
        // Intentionally fail more times than the pool size.
        for (var i = 0; i < maxConnections + 3; i++) {
          try {
            await laconic.table('__definitely_missing__').limit(1).get();
            fail('Expected query against missing table to throw');
          } on LaconicException {
            // expected
          }
        }

        // Must succeed without hanging if slots were released correctly.
        final rows = await laconic
            .select('SELECT 1 AS ok')
            .timeout(const Duration(seconds: 10));
        expect(rows, isNotEmpty);
        expect(rows.first['ok'], 1);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'connection pool returns slots after parameterized query errors',
      () async {
        for (var i = 0; i < maxConnections + 3; i++) {
          try {
            await laconic.select(
              'SELECT * FROM __definitely_missing__ WHERE id = ?',
              [i],
            );
            fail('Expected parameterized query against missing table to throw');
          } on LaconicException {
            // expected
          }
        }

        final rows = await laconic
            .select('SELECT ? AS ok', [42])
            .timeout(const Duration(seconds: 10));
        expect(rows, isNotEmpty);
        expect(rows.first['ok'], 42);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'connection pool returns slots after failed transactions',
      () async {
        for (var i = 0; i < maxConnections + 3; i++) {
          try {
            await laconic.transaction(() async {
              await laconic.table('__definitely_missing__').limit(1).get();
            });
            fail('Expected transaction to throw');
          } on LaconicException {
            // expected
          }
        }

        final rows = await laconic
            .select('SELECT 1 AS ok')
            .timeout(const Duration(seconds: 10));
        expect(rows, isNotEmpty);
        expect(rows.first['ok'], 1);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
