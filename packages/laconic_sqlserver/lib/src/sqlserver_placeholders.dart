import 'package:laconic/laconic.dart';

/// Converts positional bindings to SQL Server parameters without touching SQL
/// literals, quoted identifiers, line comments or nested block comments.
class SqlserverPlaceholders {
  static ({String sql, Map<String, Object?> parameters}) compile(
    String sql,
    List<Object?> bindings,
  ) {
    var prefix = 'laconic_p';
    while (sql.contains('@$prefix')) {
      prefix = '${prefix}_';
    }
    final output = StringBuffer();
    final parameters = <String, Object?>{};
    var i = 0;
    var index = 0;
    while (i < sql.length) {
      final char = sql[i];
      if (char == "'" || char == '"' || char == '[') {
        final closing = char == '[' ? ']' : char;
        output.write(char);
        i++;
        while (i < sql.length) {
          final current = sql[i++];
          output.write(current);
          if (current != closing) continue;
          if (i < sql.length && sql[i] == closing) {
            output.write(sql[i++]);
          } else {
            break;
          }
        }
      } else if (sql.startsWith('--', i)) {
        final end = sql.indexOf('\n', i);
        final next = end < 0 ? sql.length : end + 1;
        output.write(sql.substring(i, next));
        i = next;
      } else if (sql.startsWith('/*', i)) {
        var depth = 1;
        output.write('/*');
        i += 2;
        while (i < sql.length && depth > 0) {
          if (sql.startsWith('/*', i)) {
            depth++;
            output.write('/*');
            i += 2;
          } else if (sql.startsWith('*/', i)) {
            depth--;
            output.write('*/');
            i += 2;
          } else {
            output.write(sql[i++]);
          }
        }
      } else if (char == '?') {
        if (index >= bindings.length) {
          throw LaconicException(
            'SQL Server placeholder count exceeds binding count',
          );
        }
        final name = '$prefix$index';
        parameters[name] = bindings[index++];
        output.write('@$name');
        i++;
      } else {
        output.write(char);
        i++;
      }
    }
    if (index != bindings.length) {
      throw LaconicException(
        'SQL Server binding count exceeds placeholder count',
      );
    }
    return (sql: output.toString(), parameters: parameters);
  }
}
