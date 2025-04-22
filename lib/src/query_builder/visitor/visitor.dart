import 'package:laconic/src/query_builder/ast_node.dart';

abstract class SqlVisitor {
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

  void visitOrdering(Ordering ordering);

  void visitSelect(SelectNode node);

  void visitDelete(DeleteNode node);

  void visitUpdate(UpdateNode node);

  void visitSetClause(SetClauseNode node);

  void visitAssignment(AssignmentNode node);

  void visitInsert(InsertNode node);
}
