import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

void main() {
  test(
    'shared column metadata remains independent of caller and other rows',
    () {
      final columns = ['id', 'name'];
      final rows = LaconicResult.fromRows(columns, [
        [1, 'one'],
        [2, null],
      ]);
      columns[0] = 'changed';
      expect(rows[0]['id'], 1);
      expect(rows[1]['name'], isNull);
      expect(() => rows[0]['missing'], throwsArgumentError);
      rows[0].columns[0] = 'renamed';
      expect(rows[0]['renamed'], 1);
      expect(rows[1]['id'], 2);
      expect(rows[1].toMap(), {'id': 2, 'name': null});
    },
  );

  test('duplicate columns use last value and first position', () {
    final row =
        LaconicResult.fromRows(
          ['a', 'b', 'a'],
          [
            [1, 2, 3],
          ],
        ).single;
    expect(row.values, [3, 2]);
    expect(row.toMap(), {'a': 3, 'b': 2});
    expect(row.columns, ['a', 'b']);
  });

  test('existing constructor retains externally mutable lists', () {
    final columns = ['id'];
    final values = <Object?>[1];
    final row = LaconicResult(columns: columns, values: values);
    columns[0] = 'new';
    values[0] = 2;
    expect(row['new'], 2);
    expect(() => row['id'], throwsArgumentError);
  });
}
