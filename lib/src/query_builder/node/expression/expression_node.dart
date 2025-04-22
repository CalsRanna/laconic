import 'package:laconic/src/query_builder/node/node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

abstract class ExpressionNode extends ASTNode {
  void accept(SQLVisitor visitor);
}
