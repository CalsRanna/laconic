import 'package:laconic/src/query_builder/node/assignment_node.dart';
import 'package:laconic/src/query_builder/node/node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class SetClauseNode extends ASTNode {
  final List<AssignmentNode> assignments = [];
  void accept(SQLVisitor visitor) => visitor.visitSetClause(this);
}
