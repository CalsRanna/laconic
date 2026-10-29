/// A raw SQL expression that is output as-is during SQL compilation,
/// without parameterization or identifier wrapping.
///
/// Use [Expression.new] to create instances.
///
/// Example:
/// ```dart
/// query.selectRaw('COUNT(*) as count');
/// query.where('created_at', Expression('NOW()'), comparator: '>');
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
