/// Represents a single row from a database query result.
///
/// Provides both column-value access and map conversion capabilities.
class LaconicResult {
  /// The column names in this result row.
  final List<String> columns;

  /// The values corresponding to each column.
  final List<Object?> values;

  /// Creates a new result from columns and values lists.
  LaconicResult({required this.columns, required this.values});

  /// Creates a result from a Map of column names to values.
  ///
  /// This is the primary factory constructor used by all drivers.
  LaconicResult.fromMap(Map<String, Object?> map)
    : columns = map.keys.toList(),
      values = map.values.toList();

  /// Gets a value by column name.
  ///
  /// Throws [ArgumentError] if the column is not found.
  Object? operator [](String column) {
    var index = columns.indexOf(column);
    if (index == -1) throw ArgumentError('Column $column not found');
    return values[index];
  }

  /// Converts this result row to a Map.
  Map<String, Object?> toMap() {
    var map = <String, Object?>{};
    for (var i = 0; i < columns.length; i++) {
      map[columns[i]] = values[i];
    }
    return map;
  }
}
