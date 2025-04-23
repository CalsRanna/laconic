import 'package:laconic/src/query_builder/node/clause/clause_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class FromClauseNode extends ClauseNode {
  final String table;
  FromClauseNode(this.table);

  @override
  void accept(SQLVisitor visitor) => visitor.visitFromClause(this);
}
