import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class AssignmentNode {
  final ColumnNode column;
  final ExpressionNode value;
  AssignmentNode(this.column, this.value);

  void accept(SQLVisitor visitor) => visitor.visitAssignment(this);
}
