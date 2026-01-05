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

  /// Adds a WHERE column comparison within the JOIN clause.
  ///
  /// [first] is the first column name.
  /// [second] is the second column name.
  /// [operator] is the comparison operator (defaults to '=').
  ///
  /// Example:
  /// ```dart
  /// query.join('posts p', (join) {
  ///   join.on('u.id', 'p.user_id')
  ///       .whereColumn('p.created_at', 'p.updated_at', operator: '>');
  /// })
  /// ```
  JoinClause whereColumn(
    String first,
    String second, {
    String operator = '=',
  }) {
    _conditions.add({
      'type': 'column',
      'first': first,
      'operator': operator,
      'second': second,
      'boolean': 'and',
    });
    return this;
  }

  /// Adds an OR WHERE column comparison within the JOIN clause.
  ///
  /// [first] is the first column name.
  /// [second] is the second column name.
  /// [operator] is the comparison operator (defaults to '=').
  JoinClause orWhereColumn(
    String first,
    String second, {
    String operator = '=',
  }) {
    _conditions.add({
      'type': 'column',
      'first': first,
      'operator': operator,
      'second': second,
      'boolean': 'or',
    });
    return this;
  }

  /// Adds a WHERE NULL condition within the JOIN clause.
  ///
  /// [column] is the column name to check for NULL.
  ///
  /// Example:
  /// ```dart
  /// query.join('posts p', (join) {
  ///   join.on('u.id', 'p.user_id')
  ///       .whereNull('p.deleted_at');
  /// })
  /// ```
  JoinClause whereNull(String column) {
    _conditions.add({
      'type': 'null',
      'column': column,
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds an OR WHERE NULL condition within the JOIN clause.
  ///
  /// [column] is the column name to check for NULL.
  JoinClause orWhereNull(String column) {
    _conditions.add({
      'type': 'null',
      'column': column,
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds a WHERE NOT NULL condition within the JOIN clause.
  ///
  /// [column] is the column name to check for NOT NULL.
  ///
  /// Example:
  /// ```dart
  /// query.join('posts p', (join) {
  ///   join.on('u.id', 'p.user_id')
  ///       .whereNotNull('p.published_at');
  /// })
  /// ```
  JoinClause whereNotNull(String column) {
    _conditions.add({
      'type': 'null',
      'column': column,
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds an OR WHERE NOT NULL condition within the JOIN clause.
  ///
  /// [column] is the column name to check for NOT NULL.
  JoinClause orWhereNotNull(String column) {
    _conditions.add({
      'type': 'null',
      'column': column,
      'boolean': 'or',
      'not': true,
    });
    return this;
  }

  /// Adds a WHERE IN condition within the JOIN clause.
  ///
  /// [column] is the column name.
  /// [values] is the list of values to check against.
  ///
  /// Example:
  /// ```dart
  /// query.join('posts p', (join) {
  ///   join.on('u.id', 'p.user_id')
  ///       .whereIn('p.status', ['published', 'draft']);
  /// })
  /// ```
  JoinClause whereIn(String column, List<Object?> values) {
    _conditions.add({
      'type': 'in',
      'column': column,
      'values': values,
      'boolean': 'and',
      'not': false,
    });
    return this;
  }

  /// Adds an OR WHERE IN condition within the JOIN clause.
  ///
  /// [column] is the column name.
  /// [values] is the list of values to check against.
  JoinClause orWhereIn(String column, List<Object?> values) {
    _conditions.add({
      'type': 'in',
      'column': column,
      'values': values,
      'boolean': 'or',
      'not': false,
    });
    return this;
  }

  /// Adds a WHERE NOT IN condition within the JOIN clause.
  ///
  /// [column] is the column name.
  /// [values] is the list of values to exclude.
  ///
  /// Example:
  /// ```dart
  /// query.join('posts p', (join) {
  ///   join.on('u.id', 'p.user_id')
  ///       .whereNotIn('p.status', ['deleted', 'archived']);
  /// })
  /// ```
  JoinClause whereNotIn(String column, List<Object?> values) {
    _conditions.add({
      'type': 'in',
      'column': column,
      'values': values,
      'boolean': 'and',
      'not': true,
    });
    return this;
  }

  /// Adds an OR WHERE NOT IN condition within the JOIN clause.
  ///
  /// [column] is the column name.
  /// [values] is the list of values to exclude.
  JoinClause orWhereNotIn(String column, List<Object?> values) {
    _conditions.add({
      'type': 'in',
      'column': column,
      'values': values,
      'boolean': 'or',
      'not': true,
    });
    return this;
  }
}
