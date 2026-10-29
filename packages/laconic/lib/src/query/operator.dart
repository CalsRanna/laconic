import '../exception.dart';

abstract final class SqlOperator {
  /// Keyword operators that are safe to interpolate into SQL.
  static const Set<String> _wordOperators = {
    'like',
    'not like',
    'ilike',
    'not ilike',
    'is',
    'is not',
    'is distinct from',
    'is not distinct from',
    'regexp',
    'not regexp',
    'rlike',
    'not rlike',
    'glob',
    'not glob',
    'match',
    'against',
  };

  /// Symbol-only operators, including dialect-specific PostgreSQL/MySQL ones.
  static final RegExp _symbolOperator = RegExp(r'^[<>=!~@?&|+\-*/%^#]{1,10}$');

  /// Validates a comparison operator before it is interpolated into SQL.
  ///
  /// Comparison operators cannot be bound as parameters, so they must never
  /// carry user input verbatim. Only known SQL keyword operators and
  /// symbol-only operators are accepted; anything containing quotes,
  /// semicolons, comments or parentheses is rejected.
  static String validate(String operator) {
    final trimmed = operator.trim();
    final normalized = trimmed.toLowerCase();

    if (_wordOperators.contains(normalized) ||
        _symbolOperator.hasMatch(trimmed)) {
      return trimmed;
    }

    throw LaconicException('Invalid comparison operator: "$operator"');
  }
}
