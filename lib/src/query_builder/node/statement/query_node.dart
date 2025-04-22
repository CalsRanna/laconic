import 'package:laconic/src/query_builder/node/from_node.dart';
import 'package:laconic/src/query_builder/node/order_by/order_by_node.dart';
import 'package:laconic/src/query_builder/node/select_node.dart';
import 'package:laconic/src/query_builder/node/statement/statement_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class QueryNode extends StatementNode {
  SelectNode selectClause = SelectNode();
  OrderByNode orderByClause = OrderByNode();

  QueryNode(String table) : super(fromClause: FromNode(table));

  @override
  void accept(SQLVisitor visitor) => visitor.visitQuery(this);
}
