/// A raw SQL expression that is output as-is during SQL compilation,
/// without parameterization or identifier wrapping.
///
/// Use [raw] to create instances.
///
/// Example:
/// ```dart
/// query.selectRaw('COUNT(*) as count');
/// query.where('created_at', '>', raw('NOW()'));
/// query.orderByRaw('RANDOM()');
/// ```
class Expression {
  /// The raw SQL string.
  final String sql;

  /// Creates a raw SQL expression.
  const Expression(this.sql);

  @override
  String toString() => sql;
}

/// Creates an [Expression] wrapping a raw SQL string.
///
/// Example:
/// ```dart
/// query.select([raw('COALESCE(name, "N/A") as name'), 'email']);
/// query.where('created_at', '>', raw("datetime('now')"));
/// ```
Expression raw(String sql) => Expression(sql);
