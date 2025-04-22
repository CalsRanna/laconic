import 'package:mysql1/mysql1.dart';
import 'package:sqlite3/sqlite3.dart';

class LaconicResult {
  final List<String> columns;
  final List<Object?> values;

  LaconicResult({required this.columns, required this.values});

  LaconicResult.fromMap(Map<String, Object?> map)
    : columns = map.keys.toList(),
      values = map.values.toList();

  LaconicResult.fromResultRow(ResultRow row)
    : columns = row.fields.keys.toList(),
      values = row.fields.values.toList();

  LaconicResult.fromRow(Row row) : columns = row.keys, values = row.values;

  Object? operator [](String column) {
    var index = columns.indexOf(column);
    if (index == -1) throw ArgumentError('Column $column not found');
    return values[index];
  }

  Map<String, Object?> toMap() {
    var map = <String, Object?>{};
    for (var i = 0; i < columns.length; i++) {
      map[columns[i]] = values[i];
    }
    return map;
  }
}
