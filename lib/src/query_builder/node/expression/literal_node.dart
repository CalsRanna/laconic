import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class LiteralNode extends ExpressionNode {
  final Object? value;

  LiteralNode(this.value);

  @override
  void accept(SQLVisitor visitor) => visitor.visitLiteral(this);
}
