import 'package:laconic/src/query_builder/node/clause/clause_node.dart';
import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class SelectClauseNode extends ClauseNode {
  List<ColumnNode> columns = [];

  @override
  void accept(SQLVisitor visitor) => visitor.visitSelectClause(this);
}
