import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class ComparisonNode extends ExpressionNode {
  final ExpressionNode left;
  final String comparator;
  final ExpressionNode right;

  ComparisonNode(this.left, this.comparator, this.right);

  @override
  void accept(SQLVisitor visitor) => visitor.visitComparison(this);
}
