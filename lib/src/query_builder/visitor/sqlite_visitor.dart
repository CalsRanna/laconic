import 'package:laconic/src/query_builder/node/assignment_node.dart';
import 'package:laconic/src/query_builder/node/clause/from_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/join_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/order_by_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/select_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/set_clause_node.dart';
import 'package:laconic/src/query_builder/node/clause/where_clause_node.dart';
import 'package:laconic/src/query_builder/node/expression/column_node.dart';
import 'package:laconic/src/query_builder/node/expression/comparison_node.dart';
import 'package:laconic/src/query_builder/node/expression/literal_node.dart';
import 'package:laconic/src/query_builder/node/expression/logical_operation_node.dart';
import 'package:laconic/src/query_builder/node/ordering_node.dart';
import 'package:laconic/src/query_builder/node/statement/delete_node.dart';
import 'package:laconic/src/query_builder/node/statement/insert_node.dart';
import 'package:laconic/src/query_builder/node/statement/select_node.dart';
import 'package:laconic/src/query_builder/node/statement/update_node.dart';
import 'package:laconic/src/query_builder/visitor/visitor.dart';

class SqliteVisitor extends SQLVisitor {
  final _buffer = StringBuffer();
  final _bindings = <Object?>[];

  @override
  List<Object?> get bindings => _bindings;

  @override
  String get sql => _buffer.toString().trim();

  @override
  void visitAssignment(AssignmentNode node) {
    node.column.accept(this);
    _buffer.write(' = ?');
    if (node.value is LiteralNode) {
      _bindings.add((node.value as LiteralNode).value);
    } else {
      throw Exception('Only literal values are supported for assignments');
    }
  }

  @override
  void visitColumn(ColumnNode node) {
    _buffer.write(node.column);
  }

  @override
  void visitComparison(ComparisonNode node) {
    node.left.accept(this);
    _buffer.write(' ${node.comparator} ');
    if (node.right is LiteralNode) {
      _buffer.write('?');
      _bindings.add((node.right as LiteralNode).value);
    } else {
      node.right.accept(this);
    }
  }

  @override
  void visitDelete(DeleteNode node) {
    _reset();
    _buffer.write('delete from ');
    node.fromClause.accept(this);
    if (node.whereClause.condition != null) {
      _buffer.write(' where ');
      node.whereClause.condition!.accept(this);
    }
  }

  @override
  void visitFromClause(FromClauseNode node) {
    _buffer.write(node.table);
  }

  @override
  void visitInsert(InsertNode node) {
    _reset();
    _buffer.write('insert into ');
    node.fromClause.accept(this);
    _buffer.write(' (');
    for (var i = 0; i < node.columns.length; i++) {
      node.columns[i].accept(this);
      if (i < node.columns.length - 1) {
        _buffer.write(', ');
      }
    }
    _buffer.write(') values ');
    for (var row in node.values) {
      _buffer.write('(');
      for (var i = 0; i < row.length; i++) {
        row[i].accept(this);
        if (i < row.length - 1) {
          _buffer.write(', ');
        }
      }
      _buffer.write(')');
      if (node.values.indexOf(row) < node.values.length - 1) {
        _buffer.write(', ');
      }
    }
  }

  @override
  void visitJoinClause(JoinClauseNode node) {
    _buffer.write(' join ${node.targetTable} on ');
    node.condition.accept(this);
  }

  @override
  void visitLiteral(LiteralNode node) {
    _buffer.write('?');
    _bindings.add(node.value);
  }

  @override
  void visitLogicalOperation(LogicalOperationNode node) {
    _buffer.write('(');
    for (var i = 0; i < node.operands.length; i++) {
      node.operands[i].accept(this);
      if (i < node.operands.length - 1) {
        _buffer.write(' ${node.operator} ');
      }
    }
    _buffer.write(')');
  }

  @override
  void visitOrderByClause(OrderByClauseNode node) {
    _buffer.write(' order by ');
    for (var i = 0; i < node.orderings.length; i++) {
      node.orderings[i].accept(this);
      if (i < node.orderings.length - 1) {
        _buffer.write(', ');
      }
    }
  }

  @override
  void visitOrdering(OrderingNode ordering) {
    ordering.expression.accept(this);
    _buffer.write(' ${ordering.direction}');
  }

  @override
  void visitSelect(SelectNode node) {
    _reset();
    node.selectClause.accept(this);
    _buffer.write(' from ');
    node.fromClause.accept(this);
    if (node.joinClauses.isNotEmpty) {
      for (var joinClause in node.joinClauses) {
        joinClause.accept(this);
      }
    }
    if (node.whereClause.condition != null) {
      _buffer.write(' where ');
      node.whereClause.condition!.accept(this);
    }
    if (node.orderByClause.orderings.isNotEmpty) {
      node.orderByClause.accept(this);
    }
    if (node.limit != null) {
      _buffer.write(' limit ?');
      _bindings.add(node.limit);
    }

    if (node.offset != null) {
      _buffer.write(' offset ?');
      _bindings.add(node.offset);
    }
  }

  @override
  void visitSelectClause(SelectClauseNode node) {
    _buffer.write('select ');
    if (node.columns.isEmpty) {
      _buffer.write('*');
    } else {
      for (var i = 0; i < node.columns.length; i++) {
        node.columns[i].accept(this);
        if (i < node.columns.length - 1) {
          _buffer.write(', ');
        }
      }
    }
  }

  @override
  void visitSetClause(SetClauseNode node) {
    for (var i = 0; i < node.assignments.length; i++) {
      node.assignments[i].accept(this);
      if (i < node.assignments.length - 1) {
        _buffer.write(', ');
      }
    }
  }

  @override
  void visitUpdate(UpdateNode node) {
    _reset();
    _buffer.write('update ');
    node.fromClause.accept(this);
    _buffer.write(' set ');
    node.setClause.accept(this);
    if (node.whereClause.condition != null) {
      _buffer.write(' where ');
      node.whereClause.condition!.accept(this);
    }
  }

  @override
  void visitWhereClause(WhereClauseNode node) {
    if (node.condition != null) {
      node.condition!.accept(this);
    }
  }

  void _reset() {
    _buffer.clear();
    _bindings.clear();
  }
}
