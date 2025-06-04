import 'package:laconic/src/driver.dart';
import 'package:laconic/src/exception.dart';
import 'package:laconic/src/laconic.dart';
import 'package:laconic/src/query_builder/node/assignment_node.dart';
import 'package:laconic/src/query_builder/node/builder/join_builder.dart';
import 'package:laconic/src/query_builder/node/clause/from_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/join_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/set_clause_node.dart';
import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/node/expression/comparison_node.dart';
import 'package:laconic/src/query_builder/node/expression/literal_node.dart';
import 'package:laconic/src/query_builder/node/expression/logical_operation_node.dart';
import 'package:laconic/src/query_builder/node/ordering_node.dart';
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

  QueryBuilder({required Laconic laconic, required String table})
    : _laconic = laconic,
      _statementNode = SelectNode(table) {
    if (_statementNode is SelectNode) {
      _statementNode.selectClause.columns.add(ColumnNode('*'));
    }
  }

  Future<int> count() async {
    var selectVisitor = _createVisitor();
    _statementNode.accept(selectVisitor);
    var results = await _laconic.select(
      selectVisitor.sql,
      selectVisitor.bindings,
    );
    return results.length;
  }

  Future<void> delete() async {
    var deleteNode = DeleteNode(
      fromClause: FromClauseNode(_statementNode.fromClause.table),
      whereClause: _statementNode.whereClause,
    );
    var deleteVisitor = _createVisitor();
    deleteNode.accept(deleteVisitor);
    await _laconic.statement(deleteVisitor.sql, deleteVisitor.bindings);
  }

  Future<LaconicResult> first() async {
    var selectVisitor = _createVisitor();
    _statementNode.accept(selectVisitor);
    var results = await _laconic.select(
      selectVisitor.sql,
      selectVisitor.bindings,
    );
    if (results.isEmpty) throw LaconicException('No record found');
    return results.first;
  }

  Future<List<LaconicResult>> get() async {
    var selectVisitor = _createVisitor();
    _statementNode.accept(selectVisitor);
    return await _laconic.select(selectVisitor.sql, selectVisitor.bindings);
  }

  Future<void> insert(List<Map<String, Object?>> data) async {
    if (data.isEmpty) {
      throw LaconicException('can not insert an empty list of data');
    }
    var columns = data.first.keys.map((key) => ColumnNode(key)).toList();
    var values =
        data.map((row) {
          return data.first.keys.map((key) => LiteralNode(row[key])).toList();
        }).toList();
    var insertNode = InsertNode(
      fromClause: FromClauseNode(_statementNode.fromClause.table),
      columns: columns,
      values: values,
    );
    var insertVisitor = _createVisitor();
    insertNode.accept(insertVisitor);
    await _laconic.statement(insertVisitor.sql, insertVisitor.bindings);
  }

  QueryBuilder join(String targetTable, void Function(JoinBuilder) builder) {
    if (_statementNode is! SelectNode) {
      throw LaconicException('join is only supported for select queries');
    }
    var joinBuilder = JoinBuilder();
    builder.call(joinBuilder);
    var condition = joinBuilder.condition;
    var joinClause = JoinClauseNode(targetTable, condition: condition);
    _statementNode.joinClauses.add(joinClause);
    return this;
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
