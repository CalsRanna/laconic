/// Represents a compiled SQL query with its bindings.
class CompiledQuery {
  /// The SQL query string.
  final String sql;

  /// The parameter bindings for the query.
  final List<Object?> bindings;

  const CompiledQuery({required this.sql, required this.bindings});
}
