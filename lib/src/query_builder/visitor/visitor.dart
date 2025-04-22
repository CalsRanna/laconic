import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/node/expression/comparison_node.dart';
import 'package:laconic/src/query_builder/node/expression/literal_node.dart';
import 'package:laconic/src/query_builder/node/expression/logical_operation_node.dart';
import 'package:laconic/src/query_builder/node/clause/from_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/order_by_clause_node.dart';
import 'package:laconic/src/query_builder/node/ordering_node.dart';
import 'package:laconic/src/query_builder/node/clause/select_clause_node.dart';
import 'package:laconic/src/query_builder/node/assignment_node.dart';
import 'package:laconic/src/query_builder/node/clause/set_clause_node.dart';
import 'package:laconic/src/query_builder/node/statement/delete_node.dart';
import 'package:laconic/src/query_builder/node/statement/insert_node.dart';
import 'package:laconic/src/query_builder/node/statement/select_node.dart';
import 'package:laconic/src/query_builder/node/statement/update_node.dart';
import 'package:laconic/src/query_builder/node/clause/where_clause_node.dart';

abstract class SQLVisitor {
  List<Object?> get bindings;

  String get sql;

  void visitColumn(ColumnNode node);

  void visitComparison(ComparisonNode node);

  void visitLiteral(LiteralNode node);

  void visitLogicalOperation(LogicalOperationNode node);

  void visitQuery(SelectNode node);

  void visitFrom(FromClauseNode node);

  void visitWhere(WhereClauseNode node);

  void visitOrderBy(OrderByClauseNode node);

  void visitOrdering(OrderingNode ordering);

  void visitSelect(SelectClauseNode node);

  void visitDelete(DeleteNode node);

  void visitUpdate(UpdateNode node);

  void visitSetClause(SetClauseNode node);

  void visitAssignment(AssignmentNode node);

  void visitInsert(InsertNode node);
}
