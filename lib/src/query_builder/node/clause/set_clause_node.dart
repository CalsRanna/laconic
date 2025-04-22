import 'package:laconic/src/query_builder/node/clause/clause_node.dart';
import 'package:laconic/src/query_builder/node/assignment_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class SetClauseNode extends ClauseNode {
  final List<AssignmentNode> assignments = [];

  @override
  void accept(SQLVisitor visitor) => visitor.visitSetClause(this);
}
