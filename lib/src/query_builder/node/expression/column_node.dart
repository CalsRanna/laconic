import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class ColumnNode extends ExpressionNode {
  final String column;

  ColumnNode(this.column);

  @override
  void accept(SQLVisitor visitor) => visitor.visitColumn(this);
}
