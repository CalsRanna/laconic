import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class SchemaMetadataRegressions {
  static void register(
    Laconic Function() createDatabase, {
    bool sqlite = false,
    String? namespace,
  }) {
    group('Schema metadata and change', () {
      const parent = 'laconic_meta_parent';
      const child = 'laconic_meta_child';
      const view = 'laconic_meta_view';
      late Laconic db;
      setUp(() async {
        db = createDatabase();
        if (sqlite) await db.statement('pragma foreign_keys = on');
        await db.statement(
          'drop view if exists ${db.grammar.quoteSchemaIdentifier(view)}',
        );
        await db.schema.dropIfExists(child);
        await db.schema.dropIfExists(parent);
        await db.schema.create(parent, (t) {
          t.id();
          t.string('code', length: 20).nullable().defaultTo('before');
          t.unique(['code'], name: 'laconic_meta_code_unique');
          t.integer('marker').nullable();
        });
        await db.schema.create(child, (t) {
          t.id();
          t.bigInteger('parent_id').nullable();
          t
              .foreign(['parent_id'], name: 'laconic_meta_parent_fk')
              .references(['id'])
              .on(parent)
              .onDelete('cascade');
          t.index(['parent_id', 'id'], name: 'laconic_meta_pair');
        });
      });
      tearDown(() async {
        try {
          await db.statement(
            'drop view if exists ${db.grammar.quoteSchemaIdentifier(view)}',
          );
          await db.schema.dropIfExists(child);
          await db.schema.dropIfExists(parent);
        } finally {
          await db.close();
        }
      });

      test('lists tables and views in the selected schema', () async {
        await db.statement(
          'create view ${db.grammar.quoteSchemaIdentifier(view)} as select ${db.grammar.wrap('id')} from ${db.grammar.wrapTable(parent)}',
        );
        expect(
          (await db.schema.getTables()).map((t) => t.name),
          containsAll([parent, child]),
        );
        final views = await db.schema.getViews(schema: namespace);
        expect(views.singleWhere((v) => v.name == view).definition, isNotEmpty);
        expect(
          (await db.schema.getTables(schema: namespace)).map((t) => t.name),
          contains(parent),
        );
      });

      test('reads column types, defaults, nullability and identity', () async {
        final columns = await db.schema.getColumns(parent);
        expect(columns.map((c) => c.name), ['id', 'code', 'marker']);
        expect(columns.first.autoIncrement, isTrue);
        expect(columns.first.nullable, isFalse);
        expect(columns[1].nullable, isTrue);
        expect(columns[1].type.toLowerCase(), contains('20'));
        expect(columns[1].defaultValue, isNotEmpty);
        final id = await db.table(parent).insertGetId({'marker': 1});
        expect(await db.table(parent).where('id', id).value('code'), 'before');
        expect(
          await db.schema.getColumnType(parent, 'code', fullDefinition: true),
          columns[1].type,
        );
        expect(await db.schema.hasColumns(parent, ['id', 'code']), isTrue);
        expect(await db.schema.hasColumns(parent, ['id', 'absent']), isFalse);
        expect(await db.schema.getColumns('laconic_no_such_table'), isEmpty);
        await expectLater(
          db.schema.getColumnType(parent, 'absent'),
          throwsA(isA<LaconicException>()),
        );
      });

      test('reads ordered indexes and foreign keys', () async {
        final indexes = await db.schema.getIndexes(parent);
        expect(indexes.singleWhere((i) => i.primary).columns, ['id']);
        expect(
          await db.schema.hasIndex(parent, ['code'], type: 'unique'),
          isTrue,
        );
        expect(await db.schema.hasIndex(child, 'laconic_meta_pair'), isTrue);
        expect(await db.schema.hasIndex(child, ['parent_id', 'id']), isTrue);
        expect(await db.schema.hasIndex(child, ['id', 'parent_id']), isFalse);
        final key = (await db.schema.getForeignKeys(child)).single;
        expect(key.columns, ['parent_id']);
        expect(key.foreignTable, parent);
        expect(key.foreignColumns, ['id']);
        expect(key.onDelete, 'cascade');
        if (!sqlite) expect(key.name, 'laconic_meta_parent_fk');
      });

      test(
        'change preserves rows, indexes, identities and referencing data',
        () async {
          final id = await db.table(parent).insertGetId({'code': 'original'});
          await db.table(child).insert([
            {'parent_id': id},
          ]);
          await db.schema.table(
            parent,
            (t) =>
                t
                    .string('code', length: 100)
                    .nullable()
                    .defaultTo('after')
                    .change(),
          );
          final code = (await db.schema.getColumns(
            parent,
          )).singleWhere((c) => c.name == 'code');
          expect(code.nullable, isTrue);
          expect(code.type.toLowerCase(), contains('100'));
          expect(code.defaultValue, isNotEmpty);
          final defaultId = await db.table(parent).insertGetId({'marker': 1});
          expect(
            await db.table(parent).where('id', defaultId).value('code'),
            'after',
          );
          expect(
            await db.table(parent).where('id', id).value('code'),
            'original',
          );
          expect(await db.table(child).count(), 1);
          expect(
            await db.schema.hasIndex(parent, ['code'], type: 'unique'),
            isTrue,
          );
          final next = await db.table(parent).insertGetId({'code': 'second'});
          expect(next, greaterThan(id));
          await expectLater(
            db.table(parent).insert([
              {'code': 'original'},
            ]),
            throwsA(isA<LaconicException>()),
          );
        },
      );

      test('change removes omitted defaults and can change types', () async {
        await db.schema.table(
          parent,
          (t) => t.integer('quantity').nullable().defaultTo(2),
        );
        final id = await db.table(parent).insertGetId({
          'code': 'a',
          'quantity': 3,
        });
        await db.schema.table(parent, (t) => t.bigInteger('quantity').change());
        final column = (await db.schema.getColumns(parent)).last;
        expect(column.defaultValue, isNull);
        expect(column.nullable, isFalse);
        expect(await db.table(parent).where('id', id).value('quantity'), 3);
        await expectLater(
          db.table(parent).insert([
            {'code': 'b'},
          ]),
          throwsA(isA<LaconicException>()),
        );
      });

      test('composite key metadata preserves declared column order', () async {
        await db.schema.drop(child);
        await db.schema.drop(parent);
        await db.schema.create(parent, (t) {
          t.integer('a');
          t.integer('b');
          t.primary(['b', 'a']);
        });
        await db.schema.create(child, (t) {
          t.integer('x');
          t.integer('y');
          t.foreign(['y', 'x']).references(['b', 'a']).on(parent);
        });
        expect(
          (await db.schema.getIndexes(
            parent,
          )).singleWhere((i) => i.primary).columns,
          ['b', 'a'],
        );
        final columns = await db.schema.getColumns(parent);
        expect(columns.map((c) => c.primaryPosition), [2, 1]);
        final foreign = (await db.schema.getForeignKeys(child)).single;
        expect(foreign.columns, ['y', 'x']);
        expect(foreign.foreignColumns, ['b', 'a']);
      });

      test('invalid change is rejected before earlier DDL executes', () async {
        await expectLater(
          db.schema.table(parent, (t) {
            t.integer('new_column').nullable();
            t.string('absent').change();
          }),
          throwsA(isA<LaconicException>()),
        );
        expect(await db.schema.hasColumn(parent, 'new_column'), isFalse);
        await expectLater(
          db.schema.create(
            'laconic_meta_invalid',
            (t) => t.integer('id').change(),
          ),
          throwsA(isA<LaconicException>()),
        );
        expect(await db.schema.hasTable('laconic_meta_invalid'), isFalse);
      });
    });
  }
}
