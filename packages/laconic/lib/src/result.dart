/// Represents a single row from a database query result.
///
/// Provides both column-value access and map conversion capabilities.
class LaconicResult {
  List<String>? _columns;
  final _ResultColumns? _schema;

  /// The column names in this result row.
  ///
  /// The list remains mutable and belongs to this row. Driver results share
  /// internal column metadata until this list is requested.
  List<String> get columns => _columns ??= List<String>.of(_schema!.names);

  /// The values corresponding to each column.
  final List<Object?> values;

  /// Creates a new result from columns and values lists.
  LaconicResult({required List<String> columns, required this.values})
    : _columns = columns,
      _schema = null;

  /// Creates a result from a map of column names to values.
  LaconicResult.fromMap(Map<String, Object?> map)
    : _schema = _ResultColumns(map.keys.toList()),
      values = map.values.toList();

  LaconicResult._(this._schema, this.values);

  /// Creates rows sharing column metadata without intermediate maps.
  ///
  /// Duplicate names keep their first position and their last value, matching
  /// map conversion. Row value lists are retained when names are unique.
  static List<LaconicResult> fromRows(
    List<String> columns,
    Iterable<List<Object?>> rows,
  ) {
    final positions = <String, int>{};
    for (var i = 0; i < columns.length; i++) {
      positions[columns[i]] = i;
    }
    final schema = _ResultColumns(positions.keys.toList());
    final duplicates = positions.length != columns.length;
    final sourceIndexes = duplicates ? positions.values.toList() : null;
    return rows.map((values) {
      return LaconicResult._(
        schema,
        sourceIndexes == null
            ? values
            : [for (final i in sourceIndexes) values[i]],
      );
    }).toList();
  }

  /// Gets a value by column name.
  ///
  /// Throws [ArgumentError] if the column is not found.
  Object? operator [](String column) {
    final index =
        _columns != null
            ? _columns!.indexOf(column)
            : _schema!.indexes[column] ?? -1;
    if (index == -1) throw ArgumentError('Column $column not found');
    return values[index];
  }

  /// Converts this result row to a map.
  Map<String, Object?> toMap() {
    final names = _columns ?? _schema!.names;
    return {for (var i = 0; i < names.length; i++) names[i]: values[i]};
  }
}

class _ResultColumns {
  final List<String> names;
  final Map<String, int> indexes;

  _ResultColumns(this.names)
    : indexes = {for (var i = 0; i < names.length; i++) names[i]: i};
}
