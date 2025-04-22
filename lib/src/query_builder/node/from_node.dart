import 'package:laconic/src/query_builder/node/node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class FromNode extends ASTNode {
  final String table;
  FromNode(this.table);

  void accept(SQLVisitor visitor) => visitor.visitFrom(this);
}
