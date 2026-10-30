import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';
import 'package:test/test.dart';

void main() {
  late Laconic db;
  setUp(() async {
    db = Laconic(SqliteDriver(SqliteConfig(':memory:')));
    await db.statement('pragma foreign_keys = on');
  });
  tearDown(() => db.close());

  test(
    'rebuild preserves checks, generated columns, indexes, triggers, views and sequence',
    () async {
      await db.statement('''create table records (
      id integer primary key autoincrement,
      label text collate nocase not null default 'a,b',
      amount integer default 1 check (amount > 0),
      derived text generated always as (label || ',' || amount) stored,
      spare text,
      constraint records_label_unique unique (label)
    )''');
      await db.statement('create table audit (record_id integer)');
      await db.statement(
        'create trigger records_insert after insert on records begin insert into audit values (new.id); end',
      );
      await db.statement(
        'create index records_amount on records (amount) where amount > 1',
      );
      await db.statement(
        'create index records_expression on records (lower(label))',
      );
      await db.statement(
        'create view records_view as select label, amount from records',
      );
      await db.statement(
        'create table children (record_id integer references records(id) on delete cascade)',
      );
      await db.statement(
        "insert into records(id, label, amount) values (100, 'first', 2)",
      );
      await db.statement('delete from records where id = 100');
      await db.statement(
        "insert into records(id, label, amount) values (1, 'kept', 3)",
      );
      await db.statement('insert into children values (1)');
      await db.schema.table(
        'records',
        (t) => t.string('label', length: 100).defaultTo('next').change(),
      );
      final metadata = await db.schema.getColumns('records');
      expect(
        metadata.singleWhere((c) => c.name == 'label').collation,
        'nocase',
      );
      expect(
        metadata.singleWhere((c) => c.name == 'derived').generation,
        "label || ',' || amount",
      );
      expect(await db.table('children').count(), 1);
      expect(await db.table('audit').count(), 2);
      expect(await db.table('records').value('derived'), 'kept,3');
      expect(await db.table('records_view').value('label'), 'kept');
      expect(await db.schema.hasIndex('records', 'records_amount'), isTrue);
      expect(
        (await db.schema.getIndexes(
          'records',
        )).singleWhere((i) => i.name == 'records_expression').columns,
        [null],
      );
      expect(await db.table('records').insertGetId({'label': 'next'}), 101);
      expect(await db.table('audit').count(), 3);
      await expectLater(
        db.table('records').insert([
          {'label': 'KEPT'},
        ]),
        throwsA(isA<LaconicException>()),
      );
      await expectLater(
        db.table('records').insert([
          {'label': 'bad', 'amount': -1},
        ]),
        throwsA(isA<LaconicException>()),
      );
      expect((await db.select('pragma foreign_keys')).single.values.single, 1);
      expect(
        (await db.select('pragma legacy_alter_table')).single.values.single,
        0,
      );
    },
  );

  test(
    'trailing column renames update indexes and views after rebuilding',
    () async {
      await db.schema.create('records', (t) {
        t.id();
        t.string('label');
        t.index(['label']);
      });
      await db.table('records').insert([
        {'label': 'kept'},
      ]);
      await db.statement(
        'create view records_view as select label from records',
      );
      await db.schema.table('records', (t) {
        t.string('label', length: 100).change();
        t.renameColumn('label', 'title');
      });
      expect(await db.schema.getColumnListing('records'), ['id', 'title']);
      expect(await db.schema.hasIndex('records', ['title']), isTrue);
      expect(await db.table('records_view').value('title'), 'kept');
    },
  );

  test(
    'failure after dropping the original table restores rows and indexes',
    () async {
      await db.close();
      var failRename = false;
      final statements = <String>[];
      db = Laconic(
        SqliteDriver(SqliteConfig(':memory:')),
        beforeQuery: (query) {
          statements.add(query.sql);
          if (failRename &&
              query.sql.startsWith('alter table') &&
              query.sql.contains('__laconic_rebuild')) {
            throw LaconicException('Injected rename failure');
          }
        },
      );
      await db.statement('pragma foreign_keys = on');
      await db.schema.create('records', (t) {
        t.id();
        t.string('label');
        t.index(['label']);
      });
      await db.table('records').insert([
        {'label': 'kept'},
      ]);
      failRename = true;
      await expectLater(
        db.schema.table('records', (t) => t.text('label').change()),
        throwsA(isA<LaconicException>()),
      );
      expect(statements, contains('drop table "main"."records"'));
      expect(await db.table('records').value('label'), 'kept');
      expect(await db.schema.getColumnType('records', 'label'), 'varchar');
      expect(await db.schema.hasIndex('records', ['label']), isTrue);
      expect(await db.schema.hasTable('__laconic_rebuild_records'), isFalse);
      expect((await db.select('pragma foreign_keys')).single.values.single, 1);
    },
  );

  test(
    'adds and drops named foreign keys and primary keys with validation',
    () async {
      await db.schema.create('parent', (t) => t.integer('id').primary());
      await db.schema.create('child', (t) {
        t.integer('id');
        t.integer('parent_id').nullable();
      });
      await db.table('parent').insert([
        {'id': 1},
      ]);
      await db.table('child').insert([
        {'id': 2, 'parent_id': 1},
      ]);
      await db.schema.table('child', (t) {
        t.primary(['id']);
        t
            .foreign(['parent_id'], name: 'child_parent_fk')
            .references(['id'])
            .on('parent')
            .onDelete('cascade');
      });
      expect(
        await db.schema.hasIndex('child', ['id'], type: 'primary'),
        isTrue,
      );
      await expectLater(
        db.table('child').insert([
          {'id': 3, 'parent_id': 9},
        ]),
        throwsA(isA<LaconicException>()),
      );
      await db.schema.table('child', (t) => t.dropForeign('child_parent_fk'));
      expect(await db.schema.getForeignKeys('child'), isEmpty);
      await db.table('child').insert([
        {'id': 3, 'parent_id': 9},
      ]);
    },
  );

  test(
    'invalid existing data rolls back the whole rebuild and restores pragmas',
    () async {
      await db.schema.create('records', (t) {
        t.id();
        t.string('label').nullable();
      });
      await db.table('records').insert([
        {'label': null},
      ]);
      await expectLater(
        db.schema.table('records', (t) {
          t.integer('added').nullable();
          t.string('label').change();
        }),
        throwsA(isA<LaconicException>()),
      );
      expect(await db.schema.getColumnListing('records'), ['id', 'label']);
      expect(await db.table('records').count(), 1);
      expect(await db.schema.hasTable('__laconic_rebuild_records'), isFalse);
      expect((await db.select('pragma foreign_keys')).single.values.single, 1);
      expect(
        (await db.select('pragma legacy_alter_table')).single.values.single,
        0,
      );
    },
  );

  test(
    'foreign key validation rolls back an invalid new relationship',
    () async {
      await db.schema.create('parent', (t) => t.integer('id').primary());
      await db.schema.create('child', (t) => t.integer('parent_id'));
      await db.table('child').insert([
        {'parent_id': 99},
      ]);
      await expectLater(
        db.schema.table(
          'child',
          (t) => t
              .foreign(['parent_id'], name: 'invalid_fk')
              .references(['id'])
              .on('parent'),
        ),
        throwsA(isA<LaconicException>()),
      );
      expect(await db.schema.getForeignKeys('child'), isEmpty);
      expect(await db.table('child').value('parent_id'), 99);
    },
  );

  test('drops indexed columns without dropping unrelated indexes', () async {
    await db.schema.create('records', (t) {
      t.id();
      t.string('obsolete');
      t.string('kept');
      t.unique(['obsolete'], name: 'obsolete_unique');
      t.index(['kept'], name: 'kept_index');
    });
    await db.table('records').insert([
      {'obsolete': 'a', 'kept': 'b'},
    ]);
    await db.schema.table('records', (t) => t.dropColumn('obsolete'));
    expect(await db.schema.getColumnListing('records'), ['id', 'kept']);
    expect(await db.schema.hasIndex('records', 'kept_index'), isTrue);
    expect(await db.schema.hasIndex('records', 'obsolete_unique'), isFalse);
    expect(await db.table('records').value('kept'), 'b');
  });

  test(
    'rejects dependent column drops and active foreign-key transactions before DDL',
    () async {
      await db.schema.create('records', (t) => t.string('label').nullable());
      await db.statement(
        'create view records_view as select label from records',
      );
      await expectLater(
        db.schema.table('records', (t) {
          t.integer('new').nullable();
          t.dropColumn('label');
        }),
        throwsA(isA<LaconicException>()),
      );
      expect(await db.schema.getColumnListing('records'), ['label']);
      await db.transaction(() async {
        await expectLater(
          db.schema.table(
            'records',
            (t) => t.text('label').nullable().change(),
          ),
          throwsA(isA<LaconicException>()),
        );
        expect(await db.schema.getColumnType('records', 'label'), 'varchar');
      });
    },
  );

  test('uses savepoints within a foreign-keys-off transaction', () async {
    await db.statement('pragma foreign_keys = off');
    await db.schema.create('records', (t) => t.string('label').nullable());
    await db.transaction(() async {
      await db.table('records').insert([
        {'label': null},
      ]);
      await expectLater(
        db.schema.table('records', (t) => t.string('label').change()),
        throwsA(isA<LaconicException>()),
      );
      expect(await db.table('records').count(), 1);
      await db.schema.table(
        'records',
        (t) => t.text('label').nullable().change(),
      );
    });
    expect(await db.schema.getColumnType('records', 'label'), 'text');
    expect((await db.select('pragma foreign_keys')).single.values.single, 0);
  });

  test(
    'rebuilds attached and WITHOUT ROWID tables preserving rowids and defaults',
    () async {
      await db.statement("attach database ':memory:' as other");
      await db.statement(
        "create table other.records (code text primary key, value text default 'x,y') without rowid",
      );
      await db.statement("insert into other.records values ('a', 'b')");
      await db.schema.table(
        'other.records',
        (t) => t.text('value').nullable().defaultTo('new').change(),
      );
      expect(await db.table('other.records').value('value'), 'b');
      expect(
        (await db.schema.getTables(schema: 'other')).single.name,
        'records',
      );
      await db.statement('create table plain (value text)');
      await db.statement("insert into plain(rowid, value) values (99, 'kept')");
      await db.schema.table(
        'plain',
        (t) => t.text('value').nullable().change(),
      );
      expect(
        (await db.select('select rowid from plain')).single.values.single,
        99,
      );
      await db.schema.table(
        'plain',
        (t) => t
            .timestamp('created')
            .defaultTo(const Expression('CURRENT_TIMESTAMP')),
      );
      expect(await db.table('plain').value('created'), isNotNull);
    },
  );
}
