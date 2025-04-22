import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/node/expression/comparison_node.dart';
import 'package:laconic/src/query_builder/node/expression/literal_node.dart';
import 'package:laconic/src/query_builder/node/expression/logical_operation_node.dart';
import 'package:laconic/src/query_builder/node/from_node.dart';
import 'package:laconic/src/query_builder/node/order_by/order_by_node.dart';
import 'package:laconic/src/query_builder/node/order_by/ordering_node.dart';
import 'package:laconic/src/query_builder/node/select_node.dart';
import 'package:laconic/src/query_builder/node/set/assignment_node.dart';
import 'package:laconic/src/query_builder/node/set/set_clause_node.dart';
import 'package:laconic/src/query_builder/node/statement/delete_node.dart';
import 'package:laconic/src/query_builder/node/statement/insert_node.dart';
import 'package:laconic/src/query_builder/node/statement/query_node.dart';
import 'package:laconic/src/query_builder/node/statement/update_node.dart';
import 'package:laconic/src/query_builder/node/where_node.dart';

abstract class SQLVisitor {
  List<Object?> get bindings;

  String get sql;

  void visitColumn(ColumnNode node);

  void visitComparison(ComparisonNode node);

  void visitLiteral(LiteralNode node);

  void visitLogicalOperation(LogicalOperationNode node);

  void visitQuery(QueryNode node);

  void visitFrom(FromNode node);

  void visitWhere(WhereNode node);

  void visitOrderBy(OrderByNode node);

  void visitOrdering(OrderingNode ordering);

  void visitSelect(SelectNode node);

  void visitDelete(DeleteNode node);

  void visitUpdate(UpdateNode node);

  void visitSetClause(SetClauseNode node);

  void visitAssignment(AssignmentNode node);

  void visitInsert(InsertNode node);
}
