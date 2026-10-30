import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';
import 'package:test/test.dart';

void main() {
  group('PostgreSQL scalar subquery bindings', () {
    const table = 'laconic_numbered_subqueries';
    late Laconic db;
    QueryBuilder value() => db
        .table('$table n')
        .selectRaw(
          r"case when '?' = '?' and '$9' = '$9' "
          r'then $2::int - $1::int + $2::int end',
          [3, 10],
        )
        .where('n.id', 1);

    setUpAll(() async {
      db = Laconic(
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
      await db.schema.dropIfExists(table);
      await db.schema.create(table, (t) {
        t.integer('id').primary();
        t.integer('value');
        t.integer('other');
        t.string('label');
      });
      await db.table(table).insert([
        for (var id = 1; id <= 3; id++)
          {'id': id, 'value': 0, 'other': 0, 'label': 'initial'},
      ]);
    });
    tearDownAll(() async {
      try {
        await db.schema.dropIfExists(table);
      } finally {
        await db.close();
      }
    });

    test(
      'left and right subqueries preserve repeated and reordered parameters',
      () async {
        final leaf = value();
        final nested = db.table(table).selectSub(leaf, 'answer').where('id', 1);
        final row =
            await db
                .table(table)
                .selectRaw('?::text as marker', ['outer'])
                .where('id', 1)
                .where(nested, leaf)
                .where(leaf, 17)
                .first();
        expect(row['marker'], 'outer');
        expect(leaf.getBindings(), [3, 10, 1]);
      },
    );

    test(
      'ORDER BY retains nested JSON operators and repeated parameters',
      () async {
        final order = db
            .table('$table n')
            .selectRaw(
              r'''case when '{"key": 1}'::jsonb ?? ? then '''
              r'$2::int - $1::int + $2::int - n.id end',
              [3, 10, 'key'],
            )
            .whereColumn('n.id', 'u.id');
        // Raw question parameters follow the largest numbered parameter.
        final rows =
            await db
                .table('$table u')
                .select(['u.id'])
                .selectRaw('?::text as marker', ['outer'])
                .where('u.id', 0, comparator: '>')
                .orderBy(order)
                .get();
        expect(rows.map((r) => r['id']), [3, 2, 1]);
        expect(rows.map((r) => r['marker']), everyElement('outer'));
      },
    );

    test(
      'UPDATE rebases sibling subqueries and subsequent WHERE bindings',
      () async {
        final sub = value();
        final repeated = db
            .table(table)
            .selectRaw(r'$1::int + $1::int', [5])
            .where('id', 1);
        expect(
          await db.table(table).where('id', 2).where(sub, 17).update({
            'label': r'updated ? $1',
            'value': sub,
            'other': repeated,
          }),
          1,
        );
        final row = await db.table(table).where('id', 2).first();
        expect(row['value'], 17);
        expect(row['other'], 10);
        expect(row['label'], r'updated ? $1');
        expect(sub.getBindings(), [3, 10, 1]);
      },
    );

    test('UPDATE FROM accepts scalar subquery values', () async {
      expect(
        await db
            .table('$table u')
            .whereColumn('u.id', 's.id')
            .where('u.id', 3)
            .updateFrom('$table s', {'value': value()}),
        1,
      );
      expect(await db.table(table).where('id', 3).value('value'), 17);
    });
  });
}
