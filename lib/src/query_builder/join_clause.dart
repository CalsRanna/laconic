import 'package:laconic/src/exception.dart';

/// Helper class for building JOIN clause conditions.
///
/// This class exists separately because JOIN conditions are more complex
/// than simple WHERE conditions. Laravel supports:
/// - Multiple ON conditions (with AND/OR)
/// - WHERE conditions within JOINs
/// - Complex nested conditions
///
/// Example in Laravel:
/// ```php
/// DB::table('users')
///     ->join('contacts', function (JoinClause $join) {
///         $join->on('users.id', '=', 'contacts.user_id')
///              ->orOn('users.email', '=', 'contacts.email')
///              ->where('contacts.user_id', '>', 5);
///     })
///     ->get();
/// ```
class JoinClause {
  final List<Map<String, dynamic>> _conditions = [];

  /// Gets the list of join conditions.
  List<Map<String, dynamic>> get conditions {
    if (_conditions.isEmpty) {
      throw LaconicException('Join condition cannot be empty');
    }
    return _conditions;
  }

  /// Adds an ON condition to the join.
  ///
  /// [leftColumn] is the column from the left table (can include table prefix).
  /// [rightColumn] is the column from the right table (can include table prefix).
  /// [operator] is the comparison operator (defaults to '=').
  /// [boolean] is the boolean operator ('and' or 'or', defaults to 'and').
  JoinClause on(
    String leftColumn,
    String rightColumn, {
    String operator = '=',
    String boolean = 'and',
  }) {
    _conditions.add({
      'type': 'on',
      'left': leftColumn,
      'operator': operator,
      'right': rightColumn,
      'boolean': boolean,
    });
    return this;
  }

  /// Adds an OR ON condition to the join.
  ///
  /// [leftColumn] is the column from the left table.
  /// [rightColumn] is the column from the right table.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.join('contacts c', (join) {
  ///   join.on('u.id', 'c.user_id')
  ///       .orOn('u.email', 'c.email');
  /// })
  /// ```
  JoinClause orOn(
    String leftColumn,
    String rightColumn, {
    String operator = '=',
  }) {
    return on(leftColumn, rightColumn, operator: operator, boolean: 'or');
  }

  /// Adds a WHERE condition within the JOIN clause.
  ///
  /// [column] is the column name.
  /// [value] is the value to compare.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.join('contacts c', (join) {
  ///   join.on('u.id', 'c.user_id')
  ///       .where('c.active', true);
  /// })
  /// ```
  JoinClause where(String column, Object? value, {String operator = '='}) {
    _conditions.add({
      'type': 'where',
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR WHERE condition within the JOIN clause.
  ///
  /// [column] is the column name.
  /// [value] is the value to compare.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.join('contacts c', (join) {
  ///   join.on('u.id', 'c.user_id')
  ///       .where('c.type', 'primary')
  ///       .orWhere('c.type', 'secondary');
  /// })
  /// ```
  JoinClause orWhere(String column, Object? value, {String operator = '='}) {
    _conditions.add({
      'type': 'where',
      'column': column,
      'operator': operator,
      'value': value,
      'boolean': 'or',
    });
    return this;
  }
}
