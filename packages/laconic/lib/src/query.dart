/// Represents a SQL query with its bindings.
///
/// Used for query logging and debugging purposes.
class LaconicQuery {
  /// The parameter bindings for the query.
  final List<Object?> bindings;

  /// The SQL query string.
  final String sql;

  /// The timestamp when this query was created.
  final DateTime timestamp;

  /// Creates a new query representation.
  LaconicQuery({required this.bindings, required this.sql})
    : timestamp = DateTime.now();

  /// Returns the SQL with bindings substituted inline.
  ///
  /// **WARNING**: This method is for debugging only. The returned SQL
  /// should NEVER be executed directly as it may be vulnerable to SQL injection.
  /// Always use parameterized queries for execution.
  @Deprecated('For debugging only. Do not execute the returned SQL directly.')
  String get rawSql {
    var realSql = sql;
    for (var binding in bindings) {
      realSql = realSql.replaceFirst('?', binding.toString());
    }
    return realSql;
  }
}
