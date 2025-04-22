import 'package:laconic/src/query_builder/node/clause/clause_node.dart';
import 'package:laconic/src/query_builder/node/ordering_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class OrderByClauseNode extends ClauseNode {
  List<OrderingNode> orderings = [];

  @override
  void accept(SQLVisitor visitor) => visitor.visitOrderBy(this);
}
