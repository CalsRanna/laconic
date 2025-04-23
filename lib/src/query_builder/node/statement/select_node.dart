import 'package:laconic/src/query_builder/node/clause/from_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/join_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/order_by_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/select_clause_node.dart';
import 'package:laconic/src/query_builder/node/statement/statement_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class SelectNode extends StatementNode {
  List<JoinClauseNode> joinClauses = [];
  OrderByClauseNode orderByClause = OrderByClauseNode();
  SelectClauseNode selectClause = SelectClauseNode();

  SelectNode(String table) : super(fromClause: FromClauseNode(table));

  @override
  void accept(SQLVisitor visitor) => visitor.visitQuery(this);
}
