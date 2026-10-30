import 'dart:typed_data';

import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

abstract final class SchemaTypeRegressions {
  static void register(
    Laconic Function() createDatabase, {
    required bool sqlite,
    String? namespace,
  }) {
    group('Schema shortcuts and advanced types', () {
      const parent = 'laconic_types_parent';
      const child = 'laconic_types_child';
      const altered = 'laconic_types_altered';
      final postgres = namespace == 'public';
      final sqlserver = namespace == 'dbo';
      late Laconic db;
      setUp(() async {
        db = createDatabase();
        if (sqlite) await db.statement('pragma foreign_keys = on');
        for (final table in [child, parent, altered]) {
          await db.schema.dropIfExists(table);
        }
      });
      tearDown(() async {
        try {
          for (final table in [child, parent, altered]) {
            await db.schema.dropIfExists(table);
          }
        } finally {
          await db.close();
        }
      });

      test(
        'foreignId and lifecycle shortcuts enforce and remove their schema',
        () async {
          await db.schema.create(parent, (t) {
            t.id();
            t.integer('marker');
          });
          await db.schema.create(child, (t) {
            t.id();
            t
                .foreignId('parent_id')
                .nullable()
                .constrained(parent)
                .nullOnDelete();
            t.timestamps(precision: 3);
            t.softDeletes();
            t.rememberToken();
            t.nullableMorphs('subject');
            t.uuidMorphs('related', indexName: 'types_related_index');
            t.nullableUlidMorphs('owner');
          });
          final columns = await db.schema.getColumns(child);
          for (final name in [
            'parent_id',
            'created_at',
            'updated_at',
            'deleted_at',
            'remember_token',
            'subject_type',
            'subject_id',
            'owner_type',
            'owner_id',
          ]) {
            expect(
              columns.singleWhere((c) => c.name == name).nullable,
              isTrue,
              reason: name,
            );
          }
          expect(
            await db.schema.hasIndex(child, ['subject_type', 'subject_id']),
            isTrue,
          );
          expect(
            await db.schema.hasIndex(child, 'types_related_index'),
            isTrue,
          );
          final id = await db.table(parent).insertGetId({'marker': 1});
          await db.table(child).insert([
            {
              'parent_id': id,
              'related_type': 'item',
              'related_id': '550e8400-e29b-41d4-a716-446655440000',
            },
          ]);
          await db.table(parent).where('id', id).delete();
          expect((await db.table(child).first())['parent_id'], isNull);
          await db.schema.table(child, (t) {
            t.dropConstrainedForeignId('parent_id');
            t.dropMorphs('subject');
            t.dropMorphs('related', indexName: 'types_related_index');
            t.dropMorphs('owner');
            t.dropTimestamps();
            t.dropSoftDeletes();
            t.dropRememberToken();
          });
          expect(await db.schema.getColumnListing(child), ['id']);
          expect(await db.table(child).count(), 1);
        },
      );

      test(
        'UUID and ULID foreign shortcuts match their referenced keys',
        () async {
          await db.schema.create(parent, (t) {
            t.uuid('uuid').primary();
            t.ulid('ulid').unique();
          });
          await db.schema.create(child, (t) {
            t.id();
            t
                .foreignUuid('uuid')
                .constrained(parent, column: 'uuid')
                .noActionOnDelete();
            t
                .foreignUlid('ulid')
                .constrained(parent, column: 'ulid')
                .cascadeOnDelete();
          });
          const uuid = '550e8400-e29b-41d4-a716-446655440000';
          const ulid = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
          await db.table(parent).insert([
            {'uuid': uuid, 'ulid': ulid},
          ]);
          await db.table(child).insert([
            {'uuid': uuid, 'ulid': ulid},
          ]);
          expect(await db.schema.getForeignKeys(child), hasLength(2));
          await expectLater(
            db.table(child).insert([
              {'uuid': uuid, 'ulid': '01ARZ3NDEKTSV4RRFFQ69G5FAA'},
            ]),
            throwsA(isA<LaconicException>()),
          );
        },
      );

      test(
        'portable type families store values and expose native metadata',
        () async {
          await db.schema.create(parent, (t) {
            t.increments('id');
            t.tinyInteger('tiny').defaultTo(7);
            t.smallInteger('small').defaultTo(1024);
            t.mediumInteger('medium').defaultTo(100000);
            t.char('code', length: 3);
            t.tinyText('tiny_text').nullable();
            t.mediumText('medium_text').nullable();
            t.longText('long_text').nullable();
            t.float('score', precision: 24).defaultTo(1.5);
            t.jsonb('payload').nullable();
            t.ulid('token').nullable();
            t.dateTime('created', precision: 3).nullable();
            t.time('clock', precision: 3).nullable();
            t.year('year').nullable();
            t.ipAddress('ip').nullable();
            t.macAddress('mac').nullable();
            t
                .enumColumn('state', ["O'Reilly", '中文', 'published'])
                .defaultTo("O'Reilly");
          });
          await db.table(parent).insert([
            {
              'code': 'ABC',
              'year': 2026,
              'ip': '2001:db8::1',
              'mac': '08:00:2b:01:02:03',
            },
          ]);
          final row = await db.table(parent).first();
          expect(row['state'], "O'Reilly");
          expect(row['code'], 'ABC');
          expect((row['score'] as num).toDouble(), closeTo(1.5, 0.001));
          await expectLater(
            db.table(parent).insert([
              {'code': 'BAD', 'state': 'not allowed'},
            ]),
            throwsA(isA<LaconicException>()),
          );
          expect(await db.table(parent).count(), 1);
          final columns = await db.schema.getColumns(parent);
          expect(columns, hasLength(17));
          if (postgres) {
            expect(
              columns.singleWhere((c) => c.name == 'payload').typeName,
              'jsonb',
            );
            expect(columns.singleWhere((c) => c.name == 'ip').typeName, 'inet');
          }
          await db.schema.table(parent, (t) {
            t.longText('tiny_text').nullable().change();
            t.float('score').change();
          });
          expect(await db.table(parent).count(), 1);
        },
      );

      test('native unsigned and SET support is explicit', () async {
        if (db.grammar.supportsNativeEnum) {
          await db.schema.create(parent, (t) {
            t.bigIncrements('id').unsigned();
            t.unsignedBigInteger('size');
            t.set('flags', ['read', "O'Reilly", '中文']).nullable();
          });
          await db.table(parent).insert([
            {'size': 42, 'flags': "read,O'Reilly"},
          ]);
          expect((await db.table(parent).first())['flags'], "read,O'Reilly");
          expect(
            await db.schema.getColumnType(parent, 'size', fullDefinition: true),
            contains('unsigned'),
          );
          await db.schema.create(child, (t) {
            t.id();
            t
                .foreignId('parent_id')
                .unsigned()
                .constrained(parent)
                .cascadeOnDelete();
          });
          final id = (await db.table(parent).first())['id'];
          await db.table(child).insert([
            {'parent_id': id},
          ]);
          await db.table(parent).where('id', id).delete();
          expect(await db.table(child).count(), 0);
        } else {
          for (final define in <void Function(Blueprint)>[
            (t) => t.unsignedInteger('size'),
            (t) => t.set('flags', ['a', 'b']),
          ]) {
            await expectLater(
              db.schema.create(parent, (t) {
                t.id();
                define(t);
              }),
              throwsA(isA<LaconicException>()),
            );
            expect(await db.schema.hasTable(parent), isFalse);
          }
        }
      });

      test(
        'timezone and binary types preserve supported native semantics',
        () async {
          if (db.grammar.supportsNativeEnum) {
            await expectLater(
              db.schema.create(parent, (t) => t.timestampTz('at')),
              throwsA(isA<LaconicException>()),
            );
          } else {
            await db.schema.create(parent, (t) {
              t.id();
              t.timestampsTz(precision: 3);
              t.softDeletesTz();
              t.dateTimeTz('at', precision: 3).nullable();
              if (!sqlserver) t.timeTz('clock', precision: 3).nullable();
            });
            final type = await db.schema.getColumnType(
              parent,
              'at',
              fullDefinition: true,
            );
            expect(
              type.toLowerCase(),
              contains(
                sqlite
                    ? 'text'
                    : sqlserver
                    ? 'datetimeoffset'
                    : 'with time zone',
              ),
            );
          }
          if (sqlserver || db.grammar.supportsNativeEnum) {
            await db.schema.create(altered, (t) {
              t.id();
              t.binary('data', length: 4, fixed: true);
            });
            await db.table(altered).insert([
              {
                'data': Uint8List.fromList([0, 1, 2, 255]),
              },
            ]);
            expect((await db.table(altered).first())['data'], [0, 1, 2, 255]);
          } else {
            await expectLater(
              db.schema.create(altered, (t) => t.binary('data', length: 4)),
              throwsA(isA<LaconicException>()),
            );
            expect(await db.schema.hasTable(altered), isFalse);
          }
        },
      );

      test(
        'unsupported enum changes fail before altering existing data',
        () async {
          await db.schema.create(parent, (t) {
            t.id();
            t.enumColumn('state', ['draft', 'published']);
          });
          await db.table(parent).insert([
            {'state': 'draft'},
          ]);
          final change = db.schema.table(
            parent,
            (t) => t.enumColumn('state', ['draft', 'archived']).change(),
          );
          if (db.grammar.supportsNativeEnum) {
            await change;
            await db.table(parent).where('state', 'draft').update({
              'state': 'archived',
            });
          } else {
            await expectLater(change, throwsA(isA<LaconicException>()));
            expect((await db.table(parent).first())['state'], 'draft');
          }
        },
      );

      test(
        'geometry is native where available and never silently becomes text',
        () async {
          if (sqlite) {
            await expectLater(
              db.schema.create(parent, (t) => t.geometry('shape')),
              throwsA(isA<LaconicException>()),
            );
          } else if (postgres) {
            // The test server has no PostGIS; verify extension-backed DDL compilation.
            final blueprint =
                Blueprint(parent)
                  ..geometry('shape')
                  ..geography('earth');
            expect(
              db.grammar.compileCreateTable(blueprint).single.sql,
              contains('"earth" geography'),
            );
          } else {
            await db.schema.create(parent, (t) {
              t.id();
              t.geometry('shape').nullable();
              if (sqlserver) t.geography('earth').nullable();
            });
            expect(await db.schema.getColumnType(parent, 'shape'), 'geometry');
          }
        },
      );
    });
  }
}
