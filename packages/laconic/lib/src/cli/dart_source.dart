import 'dart:convert';

abstract final class DartSource {
  static String stringLiteral(String value) =>
      jsonEncode(value).replaceAll(r'$', r'\$');
}
