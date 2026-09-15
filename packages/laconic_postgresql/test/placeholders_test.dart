import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/src/postgresql_placeholders.dart';
import 'package:test/test.dart';

void main() {
  String compile(String sql, List<Object?> values, {int offset = 0}) =>
      PostgresqlPlaceholders.compile(sql, values, offset: offset).sql;

  test(
    'quoted strings, identifiers, dollar strings and comments are retained',
    () {
      const sql =
          '''SELECT '?', "?", 'it''s ? \$1', \$tag\$? \$1\$tag\$, \$\$?\$\$, ?
-- ? \$3
/* ? /* \$4 */ ? */ WHERE id = ?''';
      const expected =
          '''SELECT '?', "?", 'it''s ? \$1', \$tag\$? \$1\$tag\$, \$\$?\$\$, \$1
-- ? \$3
/* ? /* \$4 */ ? */ WHERE id = \$2''';
      expect(compile(sql, [1, 2]), expected);
      expect(
        compile(r"SELECT E'escaped\' ? $1', ?", [1]),
        r"SELECT E'escaped\' ? $1', $1",
      );
      expect(compile("SELECT '?' AS value", []), "SELECT '?' AS value");
    },
  );

  test('native positions are rebased without changing quoted dollars', () {
    expect(
      compile(r"id = $1 AND value = $1 AND label = '$1'", [7], offset: 2),
      r"id = $3 AND value = $3 AND label = '$1'",
    );
    expect(compile(r'SELECT $2, $1', [1, 2]), r'SELECT $2, $1');
    expect(
      compile(r'id = $1 AND other = ?', [1, 2], offset: 1),
      r'id = $2 AND other = $3',
    );
    expect(
      compile(r'SELECT identifier$1 FROM names WHERE id = ?', [1]),
      r'SELECT identifier$1 FROM names WHERE id = $1',
    );
  });

  test('JSON operators coexist with bound values', () {
    expect(
      compile('SELECT ?::jsonb ? ?', ['{}', 'key']),
      r'SELECT $1::jsonb ? $2',
    );
    expect(
      compile(r'SELECT $1::jsonb ? ?', ['{}', 'key']),
      r'SELECT $1::jsonb ? $2',
    );
    expect(
      compile('payload ?| ARRAY[?] AND payload ?& ARRAY[?]', ['a', 'b']),
      r'payload ?| ARRAY[$1] AND payload ?& ARRAY[$2]',
    );
    expect(
      compile('payload @? ?::jsonpath', [r'$.a']),
      r'payload @? $1::jsonpath',
    );
    expect(compile('payload ?? ?', ['a']), r'payload ? $1');
    expect(compile("SELECT '{}'::jsonb ? 'a'", []), "SELECT '{}'::jsonb ? 'a'");
  });

  test('binding mismatch is reported before query execution', () {
    expect(() => compile('id = ?', []), throwsA(isA<LaconicException>()));
    expect(() => compile(r'id = $2', [1]), throwsA(isA<LaconicException>()));
    expect(() => compile(r'id = $0', [1]), throwsA(isA<LaconicException>()));
  });

  test('large raw IN lists retain every binding position', () {
    final values = List<Object?>.generate(10000, (i) => i);
    final sql = 'id IN (${List.filled(values.length, '?').join(',')})';
    final result = compile(sql, values, offset: 3);
    expect(result, startsWith(r'id IN ($4,$5,'));
    expect(result, endsWith(r',$10003)'));
    expect(RegExp(r'\$\d+').allMatches(result).length, values.length);
  });
}
