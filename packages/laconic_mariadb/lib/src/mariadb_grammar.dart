import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';

/// MariaDB 10.11+ grammar, sharing the common MySQL SQL syntax.
class MariadbGrammar extends MysqlGrammar {
  @override
  String compileColumnNullability(ColumnDefinition column) {
    if (column.generationExpression != null) {
      if (!column.isNullable) {
        throw LaconicException(
          'MariaDB generated columns cannot enforce NOT NULL; explicitly use nullable()',
        );
      }
      return '';
    }
    return super.compileColumnNullability(column);
  }

  void _validateJoins(List<Map<String, dynamic>> joins) {
    if (joins.any((join) => join['type'] == 'lateral')) {
      throw LaconicException('MariaDB does not support LATERAL joins');
    }
  }

  @override
  CompiledQuery compileUpdate({
    required String table,
    required Map<String, Object?> data,
    required List<Map<String, dynamic>> wheres,
    List<Map<String, dynamic>> joins = const [],
    List<Map<String, dynamic>> orders = const [],
    int? limit,
    int? offset,
  }) {
    _validateJoins(joins);
    return super.compileUpdate(
      table: table,
      data: data,
      wheres: wheres,
      joins: joins,
      orders: orders,
      limit: limit,
      offset: offset,
    );
  }

  @override
  CompiledQuery compileDelete({
    required String table,
    required List<Map<String, dynamic>> wheres,
    List<Map<String, dynamic>> joins = const [],
    List<Map<String, dynamic>> orders = const [],
    int? limit,
    int? offset,
  }) {
    _validateJoins(joins);
    final aliased = joins.isEmpty && tableReference(table) != wrapTable(table);
    if (aliased && (orders.isNotEmpty || limit != null)) {
      throw LaconicException(
        'MariaDB 10.11 aliased DELETE does not support ORDER BY or LIMIT',
      );
    }
    final query = super.compileDelete(
      table: table,
      wheres: wheres,
      joins: joins,
      orders: orders,
      limit: limit,
      offset: offset,
    );
    // MariaDB 10.11 requires multi-table DELETE syntax for a table alias.
    return aliased
        ? CompiledQuery(
          sql: query.sql.replaceFirst(
            'delete from ',
            'delete ${tableReference(table)} from ',
          ),
          bindings: query.bindings,
        )
        : query;
  }

  @override
  CompiledQuery compileSelect({
    required String table,
    required List<Object> columns,
    required List<Map<String, dynamic>> wheres,
    required List<Map<String, dynamic>> joins,
    required List<Map<String, dynamic>> orders,
    required List<Object> groups,
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
    _validateJoins(joins);
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
