import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/node/statement/statement_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class InsertNode extends StatementNode {
  final List<ColumnNode> columns;
  final List<List<ExpressionNode>> values;
  InsertNode({
    required super.fromClause,
    required this.columns,
    required this.values,
  });
  @override
  void accept(SQLVisitor visitor) => visitor.visitInsert(this);
}
