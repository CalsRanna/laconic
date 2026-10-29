import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
import 'package:laconic_mysql/src/client/connection/connection.dart';
import 'package:laconic_mysql/src/client/connection/connection_pool.dart';
import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/protocol/packet.dart';
import 'package:test/test.dart';

class _BytesPayload extends MysqlPacketPayload {
  final Uint8List bytes;

  _BytesPayload(this.bytes);

  @override
  Uint8List encode() => bytes;
}

void main() {
  const testHost = '127.0.0.1';

  const testPort = 3306;

  const testDatabase = 'testdb';

  const testUsername = 'root';

  const testPassword = 'root';

  const testTable = 'mysql_client_audit_values';

  Future<MysqlConnection> openConnection({
    Duration commandTimeout = const Duration(seconds: 10),
  }) async {
    final connection = await MysqlConnection.createConnection(
      host: testHost,
      port: testPort,
      userName: testUsername,
      password: testPassword,
      databaseName: testDatabase,
      secure: false,
      commandTimeout: commandTimeout,
    );
    await connection.connect();
    return connection;
  }

  MysqlConfig createConfig({
    int maxConnections = 1,
    Duration commandTimeout = const Duration(seconds: 10),
  }) {
    return MysqlConfig(
      database: testDatabase,
      host: testHost,
      port: testPort,
      username: testUsername,
      password: testPassword,
      maxConnections: maxConnections,
      useSsl: false,
      commandTimeout: commandTimeout,
    );
  }

  test('secure defaults require certificate validation', () {
    const config = MysqlConfig(database: 'db', password: 'secret');

    expect(config.useSsl, isTrue);
    expect(config.allowBadCertificates, isFalse);
    expect(config.allowPublicKeyRetrieval, isTrue);
    expect(config.serverPublicKey, isNull);
    expect(
      () => MysqlConnectionPool(
        host: testHost,
        port: testPort,
        userName: testUsername,
        password: testPassword,
        maxConnections: 0,
      ),
      throwsArgumentError,
    );
  });

  test(
    'TLS rejects the test server certificate unless explicitly allowed',
    () async {
      final strictConnection = await MysqlConnection.createConnection(
        host: testHost,
        port: testPort,
        userName: testUsername,
        password: testPassword,
        databaseName: testDatabase,
        secure: true,
      );
      addTearDown(strictConnection.close);
      await expectLater(strictConnection.connect(), throwsA(isA<Exception>()));

      final developmentConnection = await MysqlConnection.createConnection(
        host: testHost,
        port: testPort,
        userName: testUsername,
        password: testPassword,
        databaseName: testDatabase,
        secure: true,
        allowBadCertificates: true,
      );
      addTearDown(developmentConnection.close);
      await developmentConnection.connect();
      expect(developmentConnection.connected, isTrue);
    },
  );

  test('caching_sha2_password authenticates over TLS', () async {
    const user = 'laconic_audit_sha2';
    const password = 'sha2-audit-password-long';
    final admin = await openConnection();
    addTearDown(admin.close);
    await admin.execute("DROP USER IF EXISTS '$user'@'%'");
    await admin.execute(
      "CREATE USER '$user'@'%' IDENTIFIED WITH caching_sha2_password "
      "BY '$password'",
    );
    addTearDown(() => admin.execute("DROP USER IF EXISTS '$user'@'%'"));

    final connection = await MysqlConnection.createConnection(
      host: testHost,
      port: testPort,
      userName: user,
      password: password,
      secure: true,
      allowBadCertificates: true,
    );
    addTearDown(connection.close);
    await connection.connect();

    final result = await connection.execute('SELECT 1 AS ok');
    expect(result.rows.single.toTypedMap(), {'ok': 1});
  });

  test(
    'caching_sha2_password authenticates over non-TLS RSA exchange',
    () async {
      const user = 'laconic_audit_sha2_plain';
      const password = 'sha2-plain-audit-password-long';
      final admin = await openConnection();
      addTearDown(admin.close);
      await admin.execute("DROP USER IF EXISTS '$user'@'%'");
      await admin.execute(
        "CREATE USER '$user'@'%' IDENTIFIED WITH caching_sha2_password "
        "BY '$password'",
      );
      addTearDown(() => admin.execute("DROP USER IF EXISTS '$user'@'%'"));

      final connection = await MysqlConnection.createConnection(
        host: testHost,
        port: testPort,
        userName: user,
        password: password,
        secure: false,
      );
      addTearDown(connection.close);
      await connection.connect();

      final result = await connection.execute('SELECT 1 AS ok');
      final tls = await connection.execute("SHOW STATUS LIKE 'Ssl_cipher'");
      expect(result.rows.single.toTypedMap(), {'ok': 1});
      expect(tls.rows.single.typedValueByName<String>('Value'), isEmpty);
    },
  );

  test('authentication timeout closes a silent socket', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final acceptedSockets = <Socket>[];
    final serverSubscription = server.listen(acceptedSockets.add);
    addTearDown(() async {
      await serverSubscription.cancel();
      for (final socket in acceptedSockets) {
        socket.destroy();
      }
      await server.close();
    });

    final connection = await MysqlConnection.createConnection(
      host: testHost,
      port: server.port,
      userName: testUsername,
      password: testPassword,
      secure: false,
      connectTimeout: const Duration(milliseconds: 150),
    );
    addTearDown(connection.close);

    await expectLater(connection.connect(), throwsA(isA<TimeoutException>()));
    expect(connection.connected, isFalse);
  });

  test('an exact 16 MiB payload includes an empty terminator packet', () {
    final packet = MysqlPacket(
      sequenceId: 9,
      payload: _BytesPayload(Uint8List(MysqlPacket.maxPhysicalPayload)),
      payloadLength: 0,
    );

    final encoded = packet.encode();
    expect(encoded.lengthInBytes, MysqlPacket.maxPhysicalPayload + 8);
    expect(encoded.sublist(0, 4), [0xff, 0xff, 0xff, 9]);
    expect(encoded.sublist(encoded.lengthInBytes - 4), [0, 0, 0, 10]);
  });

  test('pool never exceeds maxConnections during concurrent startup', () async {
    final pool = MysqlConnectionPool(
      host: testHost,
      port: testPort,
      userName: testUsername,
      password: testPassword,
      databaseName: testDatabase,
      secure: false,
      maxConnections: 2,
    );
    addTearDown(pool.close);

    var maximumActive = 0;
    await Future.wait(
      List.generate(
        10,
        (_) => pool.withConnection((_) async {
          maximumActive = max(maximumActive, pool.activeConnectionsQty);
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }),
      ),
    );

    expect(maximumActive, 2);
    expect(pool.allConnectionsQty, 2);
  });

  test(
    'close fails an in-flight command instead of leaving it pending',
    () async {
      final connection = await openConnection();
      addTearDown(connection.close);

      final query = connection.execute('SELECT SLEEP(5)');
      final queryExpectation = expectLater(
        query.timeout(const Duration(seconds: 1)),
        throwsA(isA<MysqlClientException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await connection.close();
      await queryExpectation;
    },
  );

  test('command timeout closes a stalled connection', () async {
    final connection = await openConnection(
      commandTimeout: const Duration(milliseconds: 150),
    );
    addTearDown(connection.close);

    await expectLater(
      connection.execute('SELECT SLEEP(2)'),
      throwsA(isA<TimeoutException>()),
    );
    expect(connection.connected, isFalse);
  });

  test(
    'prepare completes for a statement without parameters or columns',
    () async {
      final connection = await openConnection();
      addTearDown(connection.close);

      final statement = await connection
          .prepare('DO 1')
          .timeout(const Duration(seconds: 2));
      await statement.deallocate();
    },
  );

  test(
    'multi statements are rejected and cannot contaminate the next query',
    () async {
      final connection = await openConnection();
      addTearDown(connection.close);

      await expectLater(
        connection.execute('SET @audit_multi = 1; SELECT 42 AS stale_value'),
        throwsA(isA<MysqlServerException>()),
      );

      final result = await connection.execute('SELECT 7 AS expected_value');
      expect(result.rows.single.toTypedMap(), {'expected_value': 7});
    },
  );

  test('named text parameters are rejected instead of interpolated', () async {
    final connection = await openConnection();
    addTearDown(connection.close);

    await expectLater(
      connection.execute('SELECT :value', {'value': 1}),
      throwsA(isA<MysqlClientException>()),
    );

    final result = await connection.execute('SELECT 1 AS ok');
    expect(result.rows.single.toTypedMap(), {'ok': 1});
  });

  test('prepared parameters and binary results preserve MySQL types', () async {
    final laconic = Laconic(MysqlDriver(createConfig()));
    addTearDown(laconic.close);

    await laconic.statement('DROP TABLE IF EXISTS $testTable');
    addTearDown(() => laconic.statement('DROP TABLE IF EXISTS $testTable'));
    await laconic.statement('''
      CREATE TABLE $testTable (
        id INT PRIMARY KEY AUTO_INCREMENT,
        flag BOOLEAN NOT NULL,
        amount DOUBLE NOT NULL,
        happened_at DATETIME(6) NOT NULL,
        payload LONGBLOB NOT NULL,
        document JSON NOT NULL,
        event_year YEAR NOT NULL,
        event_date DATE NOT NULL,
        unsigned_value BIGINT UNSIGNED NOT NULL
      )
    ''');

    final timestamp = DateTime(2024, 2, 3, 4, 5, 6, 123, 456);
    final payload = Uint8List.fromList([0, 255, 1]);
    await laconic.statement(
      '''
      INSERT INTO $testTable
        (flag, amount, happened_at, payload, document, event_year,
         event_date, unsigned_value)
      VALUES (?, ?, ?, ?, ?, ?, ?, 18446744073709551615)
    ''',
      [true, 1.25, timestamp, payload, '{"a":1}', 2024, '2024-02-03'],
    );

    final matching =
        await laconic
            .table(testTable)
            .where('flag', true)
            .where('id', 1)
            .first();

    expect(matching['flag'], isTrue);
    expect(matching['amount'], 1.25);
    expect(matching['happened_at'], '2024-02-03 04:05:06.123456');
    expect(matching['payload'], isA<Uint8List>());
    expect((matching['payload'] as Uint8List).toList(), [0, 255, 1]);
    expect(matching['document'], '{"a": 1}');
    expect(matching['event_year'], 2024);
    expect(matching['event_date'], '2024-02-03');
    expect(matching['unsigned_value'], BigInt.parse('18446744073709551615'));

    final notMatching =
        await laconic.table(testTable).where('flag', false).get();
    expect(notMatching, isEmpty);
  });

  test('text and streaming results preserve unsigned BIGINT values', () async {
    final laconic = Laconic(MysqlDriver(createConfig()));
    addTearDown(laconic.close);
    final values = <Object>[
      0,
      9223372036854775807,
      BigInt.parse('9223372036854775808'),
      BigInt.parse('18446744073709551615'),
    ];
    for (final value in values) {
      final sql = 'SELECT CAST($value AS UNSIGNED) AS value';
      expect((await laconic.select(sql)).single['value'], value);
      expect(
        (await laconic.select('$sql WHERE 1 = ?', [1])).single['value'],
        value,
      );
      expect((await laconic.selectStream(sql).toList()).single['value'], value);
    }
    expect(
      (await laconic.select(
        'SELECT CAST(-9223372036854775808 AS SIGNED) AS value',
      )).single['value'],
      -9223372036854775808,
    );
  });

  test('packets larger than 16 MiB are fragmented and reassembled', () async {
    final laconic = Laconic(
      MysqlDriver(createConfig(commandTimeout: const Duration(seconds: 60))),
    );
    addTearDown(laconic.close);

    await laconic.statement('DROP TABLE IF EXISTS $testTable');
    addTearDown(() => laconic.statement('DROP TABLE IF EXISTS $testTable'));
    await laconic.statement('''
        CREATE TABLE $testTable (
          id INT PRIMARY KEY AUTO_INCREMENT,
          payload LONGBLOB NOT NULL
        )
      ''');

    final payload = Uint8List(0x00ffffff + 1024);
    payload[0] = 17;
    payload[payload.length - 1] = 29;
    final id = await laconic.table(testTable).insertGetId({'payload': payload});
    final row = await laconic.table(testTable).where('id', id).first();
    final returned = row['payload'] as Uint8List;

    expect(returned.lengthInBytes, payload.lengthInBytes);
    expect(returned.first, 17);
    expect(returned.last, 29);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test(
    'prepared statement LRU deallocates evicted server statements',
    () async {
      final laconic = Laconic(MysqlDriver(createConfig()));
      addTearDown(laconic.close);

      for (var i = 0; i < 70; i++) {
        final rows = await laconic.select('SELECT ? + $i AS value', [1]);
        expect(rows.single['value'], i + 1);
      }

      final rows = await laconic.select('''
      SELECT COUNT(*) AS statement_count
      FROM performance_schema.prepared_statements_instances
      WHERE OWNER_THREAD_ID = PS_CURRENT_THREAD_ID()
    ''');
      expect(rows.single['statement_count'], lessThanOrEqualTo(50));
    },
  );

  test('iterable results support pause, resume, and cancellation', () async {
    final connection = await openConnection();
    addTearDown(connection.close);

    final result = await connection.execute(
      '''
      WITH RECURSIVE numbers AS (
        SELECT 1 AS value
        UNION ALL
        SELECT value + 1 FROM numbers WHERE value < 200
      )
      SELECT value FROM numbers
    ''',
      null,
      true,
    );

    var seen = 0;
    await for (final row in result.rowStream) {
      seen++;
      expect(row.typedValueByName<int>('value'), seen);
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(seen, 200);

    final cancelledResult = await connection.execute(
      'SELECT value FROM (SELECT 1 AS value UNION ALL SELECT 2) values_table',
      null,
      true,
    );
    final subscription = cancelledResult.rowStream.listen((_) {});
    await subscription.cancel();

    final next = await connection
        .execute('SELECT 9 AS value')
        .timeout(const Duration(seconds: 2));
    expect(next.rows.single.toTypedMap(), {'value': 9});
  });
}
