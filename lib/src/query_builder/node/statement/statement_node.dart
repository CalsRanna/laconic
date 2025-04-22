import 'package:laconic/src/query_builder/node/clause/from_clause_node.dart';
import 'package:laconic/src/query_builder/node/node.dart';
import 'package:laconic/src/query_builder/node/clause/where_clause_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

abstract class StatementNode extends ASTNode {
  FromClauseNode fromClause;
  WhereClauseNode whereClause = WhereClauseNode();
  int? limit;
  int? offset;

  StatementNode({required this.fromClause});

  void accept(SQLVisitor visitor);
}
