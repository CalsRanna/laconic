import 'package:laconic/src/query_builder/node/statement/statement_node.dart';
import 'package:laconic/src/query_builder/node/clause/where_clause_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class DeleteNode extends StatementNode {
  DeleteNode({required super.fromClause, WhereClauseNode? whereClause}) {
    if (whereClause != null) {
      this.whereClause = whereClause;
    }
  }
  @override
  void accept(SQLVisitor visitor) {
    visitor.visitDelete(this);
  }
}
