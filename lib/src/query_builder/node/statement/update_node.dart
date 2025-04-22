import 'package:laconic/src/query_builder/node/clause/set_clause_node.dart';
import 'package:laconic/src/query_builder/node/statement/statement_node.dart';
import 'package:laconic/src/query_builder/node/clause/where_clause_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class UpdateNode extends StatementNode {
  SetClauseNode setClause;

  UpdateNode({
    required super.fromClause,
    required this.setClause,
    WhereClauseNode? whereClause,
  }) {
    if (whereClause != null) {
      this.whereClause = whereClause;
    }
  }
  @override
  void accept(SQLVisitor visitor) {
    visitor.visitUpdate(this);
  }
}
