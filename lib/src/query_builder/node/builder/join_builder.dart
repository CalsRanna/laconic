import 'package:laconic/src/exception.dart';
import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/node/expression/comparison_node.dart';
import 'package:laconic/src/query_builder/node/expression/expression_node.dart';
import 'package:laconic/src/query_builder/node/expression/logical_operation_node.dart';

class JoinBuilder {
  ExpressionNode? _condition;

  ExpressionNode get condition {
    if (_condition == null) throw LaconicException('condition is null');
    return _condition!;
  }

  JoinBuilder on(String leftColumn, String rightColumn) {
    var newCondition = ComparisonNode(
      ColumnNode(leftColumn),
      '=',
      ColumnNode(rightColumn),
    );
    if (_condition == null) {
      _condition = newCondition;
    } else {
      _condition = LogicalOperationNode('and', [_condition!, newCondition]);
    }
    return this;
  }
}
