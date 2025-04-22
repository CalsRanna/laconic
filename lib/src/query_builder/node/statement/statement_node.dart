import 'package:laconic/src/query_builder/node/from_node.dart';
import 'package:laconic/src/query_builder/node/node.dart';
import 'package:laconic/src/query_builder/node/where_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

abstract class StatementNode extends ASTNode {
  FromNode fromClause;
  WhereNode whereClause = WhereNode();
  int? limit;
  int? offset;

  StatementNode({required this.fromClause});

  void accept(SQLVisitor visitor);
}
