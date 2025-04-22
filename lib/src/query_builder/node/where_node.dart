import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/node/node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class WhereNode extends ASTNode {
  ExpressionNode? condition;

  void accept(SQLVisitor visitor) {
    if (condition == null) return;
    visitor.visitWhere(this);
  }
}
