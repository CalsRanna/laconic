import 'package:laconic/src/query_builder/node/clause/clause_node.dart';
import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class JoinClauseNode extends ClauseNode {
  final ExpressionNode condition;
  final String targetTable;

  JoinClauseNode(this.targetTable, {required this.condition});

  @override
  void accept(SQLVisitor visitor) => visitor.visitJoin(this);
}
