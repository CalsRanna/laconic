import 'package:laconic/src/query_builder/visitor/visitor.dart';

class ColumnNode extends ExpressionNode {
  final String column;

  ColumnNode(this.column);

  @override
  void accept(SqlVisitor visitor) => visitor.visitColumn(this);
}

class ComparisonNode extends ExpressionNode {
  final ExpressionNode left;
  final String comparator;
  final ExpressionNode right;

  ComparisonNode(this.left, this.comparator, this.right);

  @override
  void accept(SqlVisitor visitor) => visitor.visitComparison(this);
}

abstract class ExpressionNode {
  void accept(SqlVisitor visitor);
}

class LiteralNode extends ExpressionNode {
  final Object? value;

  LiteralNode(this.value);

  @override
  void accept(SqlVisitor visitor) => visitor.visitLiteral(this);
}

class LogicalOperationNode extends ExpressionNode {
  final String operator;
  final List<ExpressionNode> operands;

  LogicalOperationNode(this.operator, this.operands);

  @override
  void accept(SqlVisitor visitor) => visitor.visitLogicalOperation(this);
}

class SelectNode {
  List<ColumnNode> columns = [];

  void accept(SqlVisitor visitor) => visitor.visitSelect(this);
}

class FromNode {
  final String table;
  FromNode(this.table);

  void accept(SqlVisitor visitor) => visitor.visitFrom(this);
}

class WhereNode {
  ExpressionNode? condition;
  void accept(SqlVisitor visitor) {
    if (condition == null) return;
    visitor.visitWhere(this);
  }
}

class OrderByNode {
  List<Ordering> orderings = [];

  void accept(SqlVisitor visitor) => visitor.visitOrderBy(this);
}

class Ordering {
  final ExpressionNode expression;
  final String direction;
  Ordering(this.expression, this.direction);

  void accept(SqlVisitor visitor) => visitor.visitOrdering(this);
}

class QueryNode extends StatementNode {
  SelectNode selectClause = SelectNode();
  OrderByNode orderByClause = OrderByNode();

  QueryNode(String table) : super(fromClause: FromNode(table));

  @override
  void accept(SqlVisitor visitor) => visitor.visitQuery(this);
}

class DeleteNode extends StatementNode {
  DeleteNode({required super.fromClause, WhereNode? whereClause}) {
    if (whereClause != null) {
      this.whereClause = whereClause;
    }
  }
  @override
  void accept(SqlVisitor visitor) {
    visitor.visitDelete(this);
  }
}

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
  void accept(SqlVisitor visitor) {
    visitor.visitUpdate(this);
  }
}

class SetClauseNode {
  final List<AssignmentNode> assignments = [];
  void accept(SqlVisitor visitor) => visitor.visitSetClause(this);
}

class AssignmentNode {
  final ColumnNode column;
  final ExpressionNode value;
  AssignmentNode(this.column, this.value);

  void accept(SqlVisitor visitor) => visitor.visitAssignment(this);
}

abstract class StatementNode {
  FromNode fromClause;
  WhereNode whereClause = WhereNode();
  int? limit;
  int? offset;

  StatementNode({required this.fromClause});

  void accept(SqlVisitor visitor);
}

class InsertNode extends StatementNode {
  final List<ColumnNode> columns;
  final List<ExpressionNode> values;
  InsertNode({
    required super.fromClause,
    required this.columns,
    required this.values,
  });
  @override
  void accept(SqlVisitor visitor) => visitor.visitInsert(this);
}
