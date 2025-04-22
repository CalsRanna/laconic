import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/node/node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class SelectNode extends ASTNode {
  List<ColumnNode> columns = [];

  void accept(SQLVisitor visitor) => visitor.visitSelect(this);
}
