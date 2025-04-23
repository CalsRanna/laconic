class LaconicQuery {
  final List<Object?> bindings;
  final String sql;
  final DateTime timestamp;

  LaconicQuery({required this.bindings, required this.sql})
    : timestamp = DateTime.now();

  String get rawSql {
    var realSql = sql;
    for (var binding in bindings) {
      realSql = realSql.replaceFirst('?', binding.toString());
    }
    return realSql;
  }
}
