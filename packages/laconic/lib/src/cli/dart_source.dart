import 'dart:convert';

String dartString(String value) => jsonEncode(value).replaceAll(r'$', r'\$');
