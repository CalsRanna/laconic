import 'package:laconic/laconic.dart';
import 'package:test/test.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';
import '../../laconic/test/regressions/schema_regressions.dart';

void main() {
  Laconic createDatabase() => Laconic(
    PostgresqlDriver(
      const PostgresqlConfig(
        host: '127.0.0.1',
        port: 5433,
        database: 'testdb',
        username: 'postgres',
        password: 'postgres',
        useSsl: false,
      ),
    ),
  );
  SchemaRegressions.register(createDatabase, namespace: 'public');
  test('changing identity columns preserves generated values', () async {
    final db = createDatabase();
    const table = 'laconic_schema_identity';
    try {
      await db.schema.dropIfExists(table);
      await db.schema.create(table, (t) {
        t.id();
        t.string('label');
      });
      final first = await db.table(table).insertGetId({'label': 'first'});
      await db.schema.table(table, (t) => t.bigInteger('id').change());
      final second = await db.table(table).insertGetId({'label': 'second'});
      expect(second, greaterThan(first));
      expect((await db.schema.getColumns(table)).first.autoIncrement, isTrue);
      await expectLater(
        db.schema.table(table, (t) => t.bigInteger('id').defaultTo(2).change()),
        throwsA(isA<LaconicException>()),
      );
      expect(await db.table(table).count(), 2);
    } finally {
      await db.schema.dropIfExists(table);
      await db.close();
    }
  });
}
