import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';

/// MariaDB 10.11+ grammar, sharing the common MySQL SQL syntax.
class MariadbGrammar extends MysqlGrammar {
  @override
  CompiledQuery compileSelect({
    required String table,
    required List<String> columns,
    required List<Map<String, dynamic>> wheres,
    required List<Map<String, dynamic>> joins,
    required List<Map<String, dynamic>> orders,
    required List<String> groups,
    required List<Map<String, dynamic>> havings,
    required bool distinct,
    int? limit,
    int? offset,
    List<Map<String, dynamic>> locks = const [],
    List<Object?> selectBindings = const [],
    List<Object?> groupBindings = const [],
    List<String>? distinctColumns,
    CompiledQuery? fromSubquery,
    String? fromAlias,
    List<Map<String, String>> indexHints = const [],
  }) {
    if (joins.any((join) => join['type'] == 'lateral')) {
      throw LaconicException('MariaDB does not support LATERAL joins');
    }
    return super.compileSelect(
      table: table,
      columns: columns,
      wheres: wheres,
      joins: joins,
      orders: orders,
      groups: groups,
      havings: havings,
      distinct: distinct,
      limit: limit,
      offset: offset,
      locks: locks,
      selectBindings: selectBindings,
      groupBindings: groupBindings,
      distinctColumns: distinctColumns,
      fromSubquery: fromSubquery,
      fromAlias: fromAlias,
      indexHints: indexHints,
    );
  }
}
