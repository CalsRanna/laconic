import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

import '../support/mock_database.dart';

void main() {
  final grammar = MockGrammar();

  test(
    'quotes identifier segments, aliases, wildcards and embedded quotes',
    () {
      expect(grammar.wrap('order.group'), '"order"."group"');
      expect(grammar.wrap('users.*'), '"users".*');
      expect(grammar.wrap('name as result.name'), '"name" as "result.name"');
      expect(grammar.resultColumnName('name as result.name'), 'result.name');
      expect(grammar.wrap('name as order'), '"name" as "order"');
      expect(grammar.wrap('odd"name'), '"odd""name"');
      expect(grammar.wrap('"a.b"."odd""name"'), '"a.b"."odd""name"');
      expect(grammar.wrap('"a as b"'), '"a as b"');
      expect(grammar.wrapTable('order as select'), '"order" as "select"');
      expect(grammar.wrapTable('order t'), '"order" as "t"');
      expect(grammar.wrapTable('"order detail"'), '"order detail"');
      expect(
        grammar.wrapTable('order as "select detail"'),
        '"order" as "select detail"',
      );
      expect(grammar.wrap(const Expression('count(*)')), 'count(*)');
      expect(grammar.wrap('count(*)'), '"count(*)"');
    },
  );

  test(
    'parses JSON object keys and array subscripts without losing escaping',
    () {
      expect(grammar.jsonPathSegments(r'$.nested.items[0]."a.b"'), [
        'nested',
        'items',
        0,
        'a.b',
      ]);
      expect(grammar.jsonPath(r'$.nested.items[0]'), r'$."nested"."items"[0]');
      expect(
        () => grammar.jsonPath(r'$.items[bad]'),
        throwsA(isA<LaconicException>()),
      );
    },
  );
}
