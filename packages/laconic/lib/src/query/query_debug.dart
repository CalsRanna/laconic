import 'dart:typed_data';

import '../grammar/compiled_query.dart';
import '../grammar/expression.dart';

// Formats SQL for inspection only; execution always uses parameter bindings.

abstract final class QueryDebug {
  static String interpolate(
    CompiledQuery query, {
    required bool numberedPlaceholders,
  }) {
    return numberedPlaceholders
        ? _interpolateNumberedBindings(query.sql, query.bindings)
        : _interpolateQuestionBindings(query.sql, query.bindings);
  }

  static final RegExp _numberedPlaceholder = RegExp(r'\$(\d+)');

  static String _interpolateNumberedBindings(
    String sql,
    List<Object?> bindings,
  ) {
    return sql.replaceAllMapped(_numberedPlaceholder, (match) {
      final index = int.parse(match[1]!) - 1;
      if (index < 0 || index >= bindings.length) {
        return match[0]!;
      }
      return _literal(bindings[index]);
    });
  }

  static String _interpolateQuestionBindings(
    String sql,
    List<Object?> bindings,
  ) {
    final output = StringBuffer();
    var bindingIndex = 0;
    var i = 0;

    while (i < sql.length) {
      final code = sql.codeUnitAt(i);
      if (sql.startsWith('--', i)) {
        final end = sql.indexOf('\n', i + 2);
        final next = end == -1 ? sql.length : end;
        output.write(sql.substring(i, next));
        i = next;
        continue;
      }
      if (sql.startsWith('/*', i)) {
        final end = sql.indexOf('*/', i + 2);
        final next = end == -1 ? sql.length : end + 2;
        output.write(sql.substring(i, next));
        i = next;
        continue;
      }
      if (code == 39 || code == 34 || code == 96) {
        final quote = code;
        output.writeCharCode(quote);
        i++;
        while (i < sql.length) {
          final current = sql.codeUnitAt(i);
          output.writeCharCode(current);
          i++;
          if (current == quote) {
            if (i < sql.length && sql.codeUnitAt(i) == quote) {
              output.writeCharCode(quote);
              i++;
            } else {
              break;
            }
          }
        }
        continue;
      }
      if (code == 63) {
        if (bindingIndex < bindings.length) {
          output.write(_literal(bindings[bindingIndex++]));
        } else {
          output.write('?');
        }
        i++;
        continue;
      }
      output.writeCharCode(code);
      i++;
    }

    return output.toString();
  }

  static String _literal(Object? value) {
    if (value == null) return 'NULL';
    if (value is Expression) return value.sql;
    if (value is bool) return value ? '1' : '0';
    if (value is num || value is BigInt) return value.toString();
    if (value is DateTime) {
      final iso = value.toIso8601String();
      return "'${iso.substring(0, 19).replaceFirst('T', ' ')}'";
    }
    if (value is Uint8List) {
      final hex =
          value.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
      return "x'$hex'";
    }
    return "'${value.toString().replaceAll("'", "''")}'";
  }
}
