import 'package:laconic/src/query_builder/node/set/set_clause_node.dart';
import 'package:laconic/src/query_builder/node/statement/statement_node.dart';
import 'package:laconic/src/query_builder/node/where_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class UpdateNode extends StatementNode {
  SetClauseNode setClause;

  UpdateNode({
    required super.fromClause,
    required this.setClause,
    WhereNode? whereClause,
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
