import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/node/node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class OrderingNode extends ASTNode {
  final ExpressionNode expression;
  final String direction;
  OrderingNode(this.expression, this.direction);

  void accept(SQLVisitor visitor) => visitor.visitOrdering(this);
}
