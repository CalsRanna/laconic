import 'package:laconic/src/query_builder/node/clause/clause_node.dart';
import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class WhereClauseNode extends ClauseNode {
  ExpressionNode? condition;

  @override
  void accept(SQLVisitor visitor) {
    if (condition == null) return;
    visitor.visitWhere(this);
  }
}
