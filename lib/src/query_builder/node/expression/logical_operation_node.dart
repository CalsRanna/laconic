import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class LogicalOperationNode extends ExpressionNode {
  final String operator;
  final List<ExpressionNode> operands;

  LogicalOperationNode(this.operator, this.operands);

  @override
  void accept(SQLVisitor visitor) => visitor.visitLogicalOperation(this);
}
