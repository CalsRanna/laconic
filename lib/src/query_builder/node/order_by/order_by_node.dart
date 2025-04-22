import 'package:laconic/src/query_builder/node/node.dart';
import 'package:laconic/src/query_builder/node/order_by/ordering_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class OrderByNode extends ASTNode {
  List<OrderingNode> orderings = [];

  void accept(SQLVisitor visitor) => visitor.visitOrderBy(this);
}
