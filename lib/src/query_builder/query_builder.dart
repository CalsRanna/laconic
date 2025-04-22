import 'package:laconic/src/driver.dart';
import 'package:laconic/src/exception.dart';
import 'package:laconic/src/laconic.dart';
import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/node/expression/comparison_node.dart';
import 'package:laconic/src/query_builder/node/expression/literal_node.dart';
import 'package:laconic/src/query_builder/node/expression/logical_operation_node.dart';
import 'package:laconic/src/query_builder/node/clause/from_clause_node.dart';
import 'package:laconic/src/query_builder/node/ordering_node.dart';
import 'package:laconic/src/query_builder/node/assignment_node.dart';
import 'package:laconic/src/query_builder/node/clause/set_clause_node.dart';
import 'package:laconic/src/query_builder/node/statement/delete_node.dart';
import 'package:laconic/src/query_builder/node/statement/insert_node.dart';
import 'package:laconic/src/query_builder/node/statement/select_node.dart';
import 'package:laconic/src/query_builder/node/statement/statement_node.dart';
import 'package:laconic/src/query_builder/node/statement/update_node.dart';
import 'package:laconic/src/query_builder/visitor/mysql_visitor.dart';
import 'package:laconic/src/query_builder/visitor/sqlite_visitor.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';
import 'package:laconic/src/result.dart';

class QueryBuilder {
  final Laconic _laconic;
  final StatementNode _statementNode;

  List<Object?> _bindings = [];
  String _sql = '';

  QueryBuilder({required Laconic laconic, required String table})
    : _laconic = laconic,
      _statementNode = SelectNode(table) {
    if (_statementNode is SelectNode) {
      _statementNode.selectClause.columns.add(ColumnNode('*'));
    }
  }

  /// Only used to display the executed sql, may not be the real sql
  String get executedSql {
    var sql = _sql;
    for (var binding in _bindings) {
      var value = binding.toString();
      if (binding is String) value = "'$value'";
      sql = sql.replaceFirst('?', value);
    }
    return sql;
  }

  Future<void> delete() async {
    var deleteNode = DeleteNode(
      fromClause: FromClauseNode(_statementNode.fromClause.table),
      whereClause: _statementNode.whereClause,
    );
    var deleteVisitor = _createVisitor();
    deleteNode.accept(deleteVisitor);
    _bindings = deleteVisitor.bindings;
    _sql = deleteVisitor.sql;
    await _laconic.statement(deleteVisitor.sql, deleteVisitor.bindings);
  }

  Future<LaconicResult> first() async {
    var selectVisitor = _createVisitor();
    _statementNode.accept(selectVisitor);
    _bindings = selectVisitor.bindings;
    _sql = selectVisitor.sql;
    var result = await _laconic.select(
      selectVisitor.sql,
      selectVisitor.bindings,
    );
    if (result.isEmpty) throw LaconicException('No record found');
    return result.first;
  }

  Future<List<LaconicResult>> get() async {
    var selectVisitor = _createVisitor();
    _statementNode.accept(selectVisitor);
    _bindings = selectVisitor.bindings;
    _sql = selectVisitor.sql;
    return await _laconic.select(selectVisitor.sql, selectVisitor.bindings);
  }

  Future<void> insert(Map<String, Object?> data) async {
    var insertNode = InsertNode(
      fromClause: FromClauseNode(_statementNode.fromClause.table),
      columns: data.keys.map((key) => ColumnNode(key)).toList(),
      values: data.values.map((value) => LiteralNode(value)).toList(),
    );
    var insertVisitor = _createVisitor();
    insertNode.accept(insertVisitor);
    _bindings = insertVisitor.bindings;
    _sql = insertVisitor.sql;
    await _laconic.statement(insertVisitor.sql, insertVisitor.bindings);
  }

  QueryBuilder limit(int limit) {
    _statementNode.limit = limit;
    return this;
  }

  QueryBuilder offset(int offset) {
    _statementNode.offset = offset;
    return this;
  }

  QueryBuilder orderBy(String column, {String direction = 'asc'}) {
    if (_statementNode is! SelectNode) {
      throw LaconicException('order by is only supported for select queries');
    }
    _statementNode.orderByClause.orderings.add(
      OrderingNode(ColumnNode(column), direction),
    );
    return this;
  }

  QueryBuilder orWhere(
    String column,
    Object? value, {
    String comparator = '=',
  }) {
    var newCondition = ComparisonNode(
      ColumnNode(column),
      comparator,
      LiteralNode(value),
    );
    var currentCondition = _statementNode.whereClause.condition;
    if (currentCondition == null) {
      _statementNode.whereClause.condition = newCondition;
    } else {
      if (currentCondition is LogicalOperationNode &&
          currentCondition.operator == 'or') {
        currentCondition.operands.add(newCondition);
      } else {
        _statementNode.whereClause.condition = LogicalOperationNode('or', [
          currentCondition,
          newCondition,
        ]);
      }
    }
    return this;
  }

  QueryBuilder select(List<String>? columns) {
    if (_statementNode is! SelectNode) {
      throw LaconicException('select is only supported for select queries');
    }
    _statementNode.selectClause.columns.clear();
    if (columns == null || columns.isEmpty) {
      _statementNode.selectClause.columns.add(ColumnNode('*'));
    } else {
      for (var column in columns) {
        _statementNode.selectClause.columns.add(ColumnNode(column));
      }
    }
    return this;
  }

  Future<LaconicResult> sole() async {
    var selectVisitor = _createVisitor();
    _statementNode.accept(selectVisitor);
    _bindings = selectVisitor.bindings;
    _sql = selectVisitor.sql;
    var result = await _laconic.select(
      selectVisitor.sql,
      selectVisitor.bindings,
    );
    if (result.isEmpty) throw LaconicException('No record found');
    return result.first;
  }

  Future<void> update(Map<String, Object?> data) async {
    var setClause = SetClauseNode();
    data.forEach((key, value) {
      setClause.assignments.add(
        AssignmentNode(ColumnNode(key), LiteralNode(value)),
      );
    });
    var updateNode = UpdateNode(
      fromClause: FromClauseNode(_statementNode.fromClause.table),
      setClause: setClause,
      whereClause: _statementNode.whereClause,
    );
    var updateVisitor = _createVisitor();
    updateNode.accept(updateVisitor);
    _bindings = updateVisitor.bindings;
    _sql = updateVisitor.sql;
    await _laconic.statement(updateVisitor.sql, updateVisitor.bindings);
  }

  QueryBuilder where(String column, Object? value, {String comparator = '='}) {
    var newCondition = ComparisonNode(
      ColumnNode(column),
      comparator,
      LiteralNode(value),
    );
    var currentCondition = _statementNode.whereClause.condition;
    if (currentCondition == null) {
      _statementNode.whereClause.condition = newCondition;
    } else {
      if (currentCondition is LogicalOperationNode &&
          currentCondition.operator == 'and') {
        currentCondition.operands.add(newCondition);
      } else {
        _statementNode.whereClause.condition = LogicalOperationNode('and', [
          currentCondition,
          newCondition,
        ]);
      }
    }
    return this;
  }

  SQLVisitor _createVisitor() {
    if (_laconic.driver == LaconicDriver.sqlite) {
      return SqliteVisitor();
    } else {
      return MysqlVisitor();
    }
  }
}
