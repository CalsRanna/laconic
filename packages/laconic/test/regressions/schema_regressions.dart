import 'package:laconic/laconic.dart';
import 'package:test/test.dart';
import 'schema_metadata_regressions.dart';
import 'schema_type_regressions.dart';
import 'schema_feature_regressions.dart';
import 'schema_table_options_regressions.dart';

abstract final class SchemaRegressions {
  static void register(
    Laconic Function() createDatabase, {
    Future<void> Function()? prepare,
    bool sqlite = false,
    bool mariadb = false,
    String? namespace,
  }) {
    group('Schema builder', () {
      late Laconic db;
      SchemaMetadataRegressions.register(
        createDatabase,
        sqlite: sqlite,
        namespace: namespace,
      );
      SchemaTypeRegressions.register(
        createDatabase,
        sqlite: sqlite,
        namespace: namespace,
      );
      SchemaFeatureRegressions.register(
        createDatabase,
        sqlite: sqlite,
        mariadb: mariadb,
        namespace: namespace,
      );
      SchemaTableOptionsRegressions.register(
        createDatabase,
        sqlite: sqlite,
        namespace: namespace,
      );
      const users = 'laconic_schema_users';
      const posts = 'laconic_schema_posts';
      const renamed = 'laconic_schema_renamed';
      const unusual = '''schema odd'"]''';

      setUpAll(() async {
        await prepare?.call();
      });
      setUp(() async {
        db = createDatabase();
        if (sqlite) await db.statement('pragma foreign_keys = on');
        for (final table in [posts, renamed, users, unusual]) {
          await db.schema.dropIfExists(table);
        }
      });
      tearDown(() async {
        try {
          for (final table in [posts, renamed, users, unusual]) {
            await db.schema.dropIfExists(table);
          }
        } finally {
          await db.close();
        }
      });

      test(
        'creates columns, identities, literal defaults, and inspects schema',
        () async {
          expect(await db.schema.hasTable(users), isFalse);
          await db.schema.create(users, (table) {
            table.id();
            table.string('name').defaultTo("O'Reilly\\中文");
            table.boolean('active').defaultTo(true);
            table.decimal('balance', precision: 12, scale: 2).defaultTo(12.50);
            table
                .dateTime('created')
                .defaultTo(Expression('CURRENT_TIMESTAMP'));
            table.json('payload').nullable();
            table.binary('data').nullable();
            table.uuid('token').nullable();
            table.timestamps();
          });
          expect(await db.schema.hasTable(users), isTrue);
          expect(await db.schema.getColumnListing(users), [
            'id',
            'name',
            'active',
            'balance',
            'created',
            'payload',
            'data',
            'token',
            'created_at',
            'updated_at',
          ]);
          expect(await db.schema.hasColumn(users, 'missing'), isFalse);
          final firstId = await db.table(users).insertGetId({'active': false});
          final secondId = await db.table(users).insertGetId({'active': true});
          expect(secondId, greaterThan(firstId));
          final row = await db.table(users).find(firstId);
          expect(row['name'], "O'Reilly\\中文");
          expect(row['created'], isNotNull);
        },
      );

      test('alters and renames tables while preserving rows', () async {
        await db.schema.create(users, (table) {
          table.id();
          table.string('name');
        });
        await db.table(users).insert([
          {'name': 'Ada'},
        ]);
        await db.schema.table(users, (table) {
          table.integer('age').nullable();
          table.string('nickname').nullable();
          table.index(['age'], name: 'schema_age_index');
          table.renameColumn('name', 'display_name');
        });
        expect(await db.schema.getColumnListing(users), [
          'id',
          'display_name',
          'age',
          'nickname',
        ]);
        await db.schema.table(users, (table) {
          table.dropIndex('schema_age_index');
          table.dropColumn('nickname');
        });
        await db.schema.rename(users, renamed);
        expect(await db.schema.hasTable(users), isFalse);
        expect(await db.schema.hasTable(renamed), isTrue);
        expect((await db.table(renamed).first())['display_name'], 'Ada');
        await db.schema.drop(renamed);
        expect(await db.schema.hasTable(renamed), isFalse);
        await db.schema.dropIfExists(renamed);
      });

      test('unique indexes enforce uniqueness and can be dropped', () async {
        await db.schema.create(users, (table) {
          table.id();
          table.string('email');
          table.unique(['email'], name: 'schema_email_unique');
        });
        await db.table(users).insert([
          {'email': 'a@example.test'},
        ]);
        await expectLater(
          db.table(users).insert([
            {'email': 'a@example.test'},
          ]),
          throwsA(isA<LaconicException>()),
        );
        await db.schema.table(
          users,
          (table) => table.dropIndex('schema_email_unique'),
        );
        await db.table(users).insert([
          {'email': 'a@example.test'},
        ]);
        expect(await db.table(users).count(), 2);
      });

      test(
        'composite primary keys and foreign keys enforce relationships',
        () async {
          await db.schema.create(users, (table) {
            table.integer('tenant');
            table.integer('user_id');
            table.primary(['tenant', 'user_id']);
          });
          await db.schema.create(posts, (table) {
            table.id();
            table.integer('tenant');
            table.integer('user_id');
            table
                .foreign(['tenant', 'user_id'])
                .references(['tenant', 'user_id'])
                .on(users)
                .onDelete('cascade');
          });
          await db.table(users).insert([
            {'tenant': 1, 'user_id': 2},
          ]);
          await db.table(posts).insert([
            {'tenant': 1, 'user_id': 2},
          ]);
          await expectLater(
            db.table(posts).insert([
              {'tenant': 9, 'user_id': 2},
            ]),
            throwsA(isA<LaconicException>()),
          );
          await db.table(users).where('tenant', 1).delete();
          expect(await db.table(posts).count(), 0);
        },
      );

      test(
        'quotes identifiers and keeps inspection values separate from SQL',
        () async {
          const column = 'select"\'`]';
          await db.schema.create(unusual, (table) {
            table.string(column).nullable();
          });
          expect(await db.schema.hasTable(unusual), isTrue);
          expect(await db.schema.getColumnListing(unusual), [column]);
          expect(await db.schema.hasTable("no_table' or '1'='1"), isFalse);
        },
      );

      test('rejects invalid definitions before executing any DDL', () async {
        await expectLater(
          db.schema.create(users, (table) {
            table.id();
            table.dropColumn('missing');
          }),
          throwsA(isA<LaconicException>()),
        );
        expect(await db.schema.hasTable(users), isFalse);
        await expectLater(
          db.schema.create(users, (table) {
            table.id();
            table.integer('id');
          }),
          throwsA(isA<LaconicException>()),
        );
        expect(await db.schema.hasTable(users), isFalse);
      });

      if (namespace != null) {
        test(
          'qualified tables use the same namespace for indexes and inspection',
          () async {
            final qualified = '$namespace.$users';
            await db.schema.create(qualified, (table) {
              table.id();
              table.string('name');
              table.unique(['name'], name: 'schema_qualified_unique');
            });
            expect(await db.schema.hasTable(qualified), isTrue);
            expect(await db.schema.getColumnListing(qualified), ['id', 'name']);
            await db.schema.table(
              qualified,
              (table) => table.dropIndex('schema_qualified_unique'),
            );
            await db.schema.rename(qualified, renamed);
            expect(await db.schema.hasTable('$namespace.$renamed'), isTrue);
            await db.schema.drop('$namespace.$renamed');
          },
        );
      }

      if (sqlite) {
        test('SQLite can add a column and a foreign key atomically', () async {
          await db.schema.create(users, (table) => table.id());
          await db.schema.table(users, (table) {
            table.integer('new_column').nullable();
            table.foreign(['new_column']).references(['id']).on(users);
          });
          expect(await db.schema.hasColumn(users, 'new_column'), isTrue);
          expect((await db.schema.getForeignKeys(users)).single.columns, [
            'new_column',
          ]);
        });
      }
    });
  }
}
