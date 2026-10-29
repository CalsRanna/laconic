import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

import '../support/mock_database.dart';

class CustomGrammar extends MockGrammar {
  @override
  String compileColumnType(ColumnDefinition column) =>
      column.type == ColumnType.string
          ? 'varchar(${column.length})'
          : 'integer';

  @override
  CompiledQuery compileTableExists(String table) =>
      CompiledQuery(sql: 'custom table inspection ?', bindings: [table]);

  @override
  CompiledQuery compileColumnListing(String table) =>
      CompiledQuery(sql: 'custom column inspection ?', bindings: [table]);
}

class CustomDriver extends MockDriver {
  @override
  final SqlGrammar grammar = CustomGrammar();
}

void main() {
  test(
    'a custom driver uses the same schema entry point and query hooks',
    () async {
      final driver = CustomDriver();
      final before = <LaconicQuery>[];
      final after = <LaconicQuery>[];
      final db = Laconic(
        driver,
        beforeQuery: before.add,
        afterQuery: (q, _) => after.add(q),
      );
      expect(identical(db.schema, db.schema), isTrue);
      await db.schema.create('users', (table) {
        table.string('name');
        table.index(['name']);
      });
      expect(driver.executedSql, [
        'create table "users" ("name" varchar(255) not null)',
        'create index "users_name_index" on "users" ("name")',
      ]);
      driver.mockResults = [
        {'name': 'name'},
      ];
      expect(await db.schema.hasTable('users'), isTrue);
      expect(await db.schema.hasColumn('users', 'name'), isTrue);
      expect(driver.executedParams.last, ['users']);
      expect(before.map((q) => q.sql), driver.executedSql);
      expect(after.map((q) => q.sql), driver.executedSql);
    },
  );

  test(
    'invalid defaults and key definitions fail before creating a table',
    () async {
      final driver = CustomDriver();
      final db = Laconic(driver);
      for (final value in [double.nan, double.infinity, Object()]) {
        await expectLater(
          db.schema.create(
            'users',
            (table) => table.integer('id').defaultTo(value),
          ),
          throwsA(isA<LaconicException>()),
        );
      }
      await expectLater(
        db.schema.create('users', (table) {
          table.integer('id');
          table.foreign(['id']).references(['id']);
        }),
        throwsA(isA<LaconicException>()),
      );
      await expectLater(
        db.schema.create('users', (table) {
          table.integer('id');
          table.unique([]);
        }),
        throwsA(isA<LaconicException>()),
      );
      expect(driver.executedSql, isEmpty);
    },
  );

  test('unimplemented schema capabilities report a clear exception', () async {
    final db = Laconic(MockDriver());
    await expectLater(
      db.schema.create('users', (table) => table.integer('id')),
      throwsA(isA<LaconicException>()),
    );
    await expectLater(
      db.schema.hasTable('users'),
      throwsA(isA<LaconicException>()),
    );
    await expectLater(
      db.schema.getColumnListing('users'),
      throwsA(isA<LaconicException>()),
    );
  });
}
