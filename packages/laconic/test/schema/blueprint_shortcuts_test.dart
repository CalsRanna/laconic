import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

void main() {
  test('foreign column modifiers chain before explicit constraints', () {
    final blueprint = Blueprint('posts');
    final column = blueprint.foreignId('owner_id').nullable().unsigned();
    final key =
        column.constrained('accounts', column: 'key', name: 'owner_fk')
          ..cascadeOnUpdate()
          ..nullOnDelete();
    expect(blueprint.commands, [column, key]);
    expect(column.type, ColumnType.bigInteger);
    expect(column.isNullable, isTrue);
    expect(column.isUnsigned, isTrue);
    expect(key.name, 'owner_fk');
    expect(key.columns, ['owner_id']);
    expect(key.referencedTable, 'accounts');
    expect(key.referencedColumns, ['key']);
    expect(key.deleteAction, 'set null');
    expect(key.updateAction, 'cascade');
  });

  test('enum values are snapshots and invalid type parameters fail early', () {
    final blueprint = Blueprint('items');
    final values = ['draft', 'published'];
    final column = blueprint.enumColumn('state', values);
    values.add('changed');
    expect(column.allowed, ['draft', 'published']);
    expect(() => column.allowed.add('mutate'), throwsUnsupportedError);
    for (final define in <void Function()>[
      () => blueprint.char('code', length: 0),
      () => blueprint.float('score', precision: 54),
      () => blueprint.time('time', precision: -1),
      () => blueprint.timestampTz('stamp', precision: 8),
      () => blueprint.binary('data', fixed: true),
      () => blueprint.enumColumn('empty', []),
      () => blueprint.enumColumn('duplicate', ['x', 'x']),
      () => blueprint.enumColumn('nul', ['a\u0000b']),
      () => blueprint.set('comma', ['a,b']),
      () => blueprint.set('large', List.generate(65, (i) => '$i')),
    ]) {
      expect(define, throwsA(isA<LaconicException>()));
    }
    expect(blueprint.commands, [column]);
  });

  test('identity shortcuts keep the signed id convention', () {
    final blueprint = Blueprint('ids');
    final columns = [
      blueprint.id(),
      blueprint.increments('ordinary'),
      blueprint.bigIncrements('big'),
      blueprint.smallIncrements('small'),
      blueprint.mediumIncrements('medium'),
      blueprint.tinyIncrements('tiny'),
    ];
    expect(
      columns.every((c) => c.isPrimary && c.autoIncrement && !c.isUnsigned),
      isTrue,
    );
  });

  test('drop shortcuts remove constraints and indexes before columns', () {
    final blueprint = Blueprint('posts');
    blueprint.dropConstrainedForeignId('user_id');
    blueprint.dropMorphs('owner');
    blueprint.dropSoftDeletes();
    blueprint.dropRememberToken();
    blueprint.dropTimestampsTz();
    final changes = blueprint.commands.cast<SchemaChangeCommand>();
    expect(changes.map((c) => c.name), [
      'posts_user_id_foreign',
      'user_id',
      'posts_owner_type_owner_id_index',
      'owner_type',
      'owner_id',
      'deleted_at',
      'remember_token',
      'created_at',
      'updated_at',
    ]);
    expect(changes.first.change, SchemaChange.dropForeign);
    expect(changes.elementAt(2).change, SchemaChange.dropIndex);
  });
}
