import 'package:laconic/laconic.dart';

// Scans SQL once, retaining literals, comments and PostgreSQL JSON operators.
// A raw fragment uses local $N indexes; ? indexes follow its largest $N.
class PostgresqlPlaceholders {
  static final _dollarTag = RegExp(
    r'\$(?:[a-zA-Z_\u0080-\uffff][a-zA-Z_0-9\u0080-\uffff]*)?\$',
  );
  static const _expectsValue = {
    'select',
    'where',
    'and',
    'or',
    'not',
    'is',
    'in',
    'like',
    'ilike',
    'between',
    'when',
    'then',
    'else',
    'on',
    'by',
    'limit',
    'offset',
    'set',
    'values',
    'returning',
    'as',
    'case',
    'distinct',
    'having',
    'from',
    'join',
    'using',
    'exists',
    'escape',
    'any',
    'all',
  };

  static CompiledQuery compile(
    String sql,
    List<Object?> bindings, {
    int offset = 0,
  }) {
    final tokens = <_Parameter>[];
    var maximum = 0;
    var questions = 0;
    var canEndExpression = false;
    var i = 0;
    while (i < sql.length) {
      final code = sql.codeUnitAt(i);
      if (code <= 32) {
        i++;
        continue;
      }
      if (sql.startsWith('--', i)) {
        final end = sql.indexOf('\n', i + 2);
        i = end == -1 ? sql.length : end + 1;
        continue;
      }
      if (sql.startsWith('/*', i)) {
        var depth = 1;
        i += 2;
        while (i < sql.length && depth > 0) {
          if (sql.startsWith('/*', i)) {
            depth++;
            i += 2;
          } else if (sql.startsWith('*/', i)) {
            depth--;
            i += 2;
          } else {
            i++;
          }
        }
        continue;
      }
      if (code == 39 || code == 34) {
        final escaped =
            code == 39 &&
            i > 0 &&
            (sql[i - 1] == 'e' || sql[i - 1] == 'E') &&
            (i == 1 || !_identifierPart(sql.codeUnitAt(i - 2)));
        i++;
        while (i < sql.length) {
          if (escaped && sql.codeUnitAt(i) == 92) {
            i = (i + 2).clamp(0, sql.length);
          } else if (sql.codeUnitAt(i) == code) {
            i++;
            if (i < sql.length && sql.codeUnitAt(i) == code) {
              i++;
            } else {
              break;
            }
          } else {
            i++;
          }
        }
        canEndExpression = true;
        continue;
      }
      if (code == 36) {
        final tag = _dollarTag.matchAsPrefix(sql, i);
        if (tag != null) {
          final end = sql.indexOf(tag[0]!, tag.end);
          i = end == -1 ? sql.length : end + tag[0]!.length;
          canEndExpression = true;
          continue;
        }
        var end = i + 1;
        while (end < sql.length && _digit(sql.codeUnitAt(end))) {
          end++;
        }
        if (end > i + 1) {
          final number = int.parse(sql.substring(i + 1, end));
          if (number == 0) {
            throw LaconicException('PostgreSQL parameter indexes start at 1');
          }
          tokens.add(_Parameter(i, end, number));
          if (number > maximum) maximum = number;
          i = end;
          canEndExpression = true;
          continue;
        }
      }
      if (_identifierStart(code)) {
        final start = i++;
        while (i < sql.length && _identifierPart(sql.codeUnitAt(i))) {
          i++;
        }
        canEndExpression =
            !_expectsValue.contains(sql.substring(start, i).toLowerCase());
        continue;
      }
      if (_digit(code)) {
        i++;
        while (i < sql.length && (_digit(sql.codeUnitAt(i)) || sql[i] == '.')) {
          i++;
        }
        canEndExpression = true;
        continue;
      }
      if (code == 63) {
        if (sql.startsWith('??', i)) {
          // Explicit escape for a question-mark operator in an ambiguous fragment.
          tokens.add(_Parameter(i, i + 2, -1));
          i += 2;
          canEndExpression = false;
        } else if (sql.startsWith('?|', i) || sql.startsWith('?&', i)) {
          i += 2;
          canEndExpression = false;
        } else if (canEndExpression) {
          i++;
          canEndExpression = false;
        } else {
          tokens.add(_Parameter(i, i + 1, null));
          questions++;
          i++;
          canEndExpression = true;
        }
        continue;
      }
      if (sql.startsWith('@?', i)) {
        i += 2;
        canEndExpression = false;
        continue;
      }
      canEndExpression = code == 41 || code == 93; // ')' or ']'.
      i++;
    }
    final expected = maximum + questions;
    if (bindings.length != expected) {
      throw LaconicException(
        'SQL expects $expected bindings, received ${bindings.length}',
      );
    }
    if (offset == 0 && questions == 0 && !tokens.any((t) => t.number == -1)) {
      return CompiledQuery(sql: sql, bindings: bindings);
    }
    final output = StringBuffer();
    var previous = 0;
    var questionIndex = maximum;
    for (final token in tokens) {
      output.write(sql.substring(previous, token.start));
      if (token.number == -1) {
        output.write('?');
      } else {
        final number = token.number ?? ++questionIndex;
        output.write('\$${number + offset}');
      }
      previous = token.end;
    }
    output.write(sql.substring(previous));
    return CompiledQuery(sql: output.toString(), bindings: bindings);
  }

  static bool _digit(int c) => c >= 48 && c <= 57;
  static bool _identifierStart(int c) =>
      c == 95 || c >= 128 || (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
  static bool _identifierPart(int c) =>
      _identifierStart(c) || _digit(c) || c == 36;
}

class _Parameter {
  final int start;
  final int end;
  final int? number;
  _Parameter(this.start, this.end, this.number);
}
