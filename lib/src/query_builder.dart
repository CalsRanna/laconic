import 'package:laconic/src/db.dart';

class QueryBuilder {
  DB db;
  String table;
  String _columns = '*';
  String _groupBy = '';
  String _having = '';
  String _leftJoin = '';
  int _limit = 0;
  int _offset = 0;
  String _orderBy = '';
  String _rightJoin = '';
  String _set = '';
  String _sql = '';
  String _statement = '';
  String _values = '';
  String _where = '';

  QueryBuilder.from({required this.db, required this.table});

  /// Retrieve the average of the values of a given column.
  Future<double> avg(String column) async {
    _setStatement(Operator.get);
    _setColumn(column);
    _setAggraegate(Aggregate.avg);
    _buildSql();
    var results = await db.select(_sql);
    return results[0]['AVG($column)'];
  }

  /// Insert new records into the database.
  Future<int> batchInsert(List<Map<String, dynamic>> values) async {
    _setStatement(Operator.insert);
    _setColumns(values[0].keys.toList());
    List<String> clauses = [];
    for (Map value in values) {
      clauses.add(value.values.join(', '));
    }
    _values = clauses.join('), (');
    _buildSql();
    var affectedRows = await db.insert(_sql);
    return affectedRows;
  }

  /// Retrieve the "count" result of the query.
  Future<int> count() async {
    _setStatement(Operator.get);
    _setColumns(['*']);
    _setAggraegate(Aggregate.count);
    _buildSql();
    var results = await db.select(_sql);
    return results[0]['COUNT(*)'];
  }

  /// Delete records from the database.
  Future<int> delete() async {
    _setStatement(Operator.delete);
    _buildSql();
    var affectedRows = await db.delete(_sql);
    return affectedRows;
  }

  /// Execute the query and get the first result.
  Future<Map<String, dynamic>> first() async {
    _setStatement(Operator.get);
    _setLimit(1);
    _buildSql();
    var results = await db.select(_sql);
    if (results.isNotEmpty) {
      return results[0];
    } else {
      return Map.of({});
    }
  }

  /// Execute the query as a "select" statement.
  Future<List<Map<String, dynamic>>> get() async {
    _setStatement(Operator.get);
    _buildSql();
    var results = await db.select(_sql);
    return results;
  }

  /// Add a "group by" clause to the query.
  QueryBuilder groupBy(dynamic groups) {
    if (groups.runtimeType == String) {
      _groupBy = groups;
    } else {
      _groupBy = groups.join(', ');
    }
    return this;
  }

  /// Add a "having" clause to the query.
  QueryBuilder having(String column, dynamic value, [dynamic operator]) {
    String clause = '$column = $value';
    if (value.runtimeType == String) {
      clause = "$column = '$value'";
    }
    if (operator != null) {
      clause = "$column $value $operator";
      if (operator.runtimeType == String) {
        clause = "$column $value '$operator'";
      }
    }
    if (_having == "") {
      _having = clause;
    } else {
      _having = "$_having AND $clause";
    }
    return this;
  }

  /// Put the query's results in random order.
  QueryBuilder inRandomOrder() {
    _orderBy = 'RAND()';
    return this;
  }

  /// Insert a new record into the database.
  Future<int> insert(Map<String, dynamic> value) async {
    _setStatement(Operator.insert);
    _setColumns(value.keys.toList());
    _values = value.values.join(', ');
    _buildSql();
    var affectedRows = await db.insert(_sql);
    return affectedRows;
  }

  /// Add a left join to the query.
  QueryBuilder leftJoin(String table, String key, String foreignKey) {
    _leftJoin = '$table ON ${this.table}.$key = $table.$foreignKey';
    return this;
  }

  /// Set the "limit" value of the query.
  QueryBuilder limit(int value) {
    _setLimit(value);
    return this;
  }

  /// Retrieve the maximum value of a given column.
  Future<int> max(String column) async {
    _setStatement(Operator.get);
    _setColumn(column);
    _setAggraegate(Aggregate.max);
    _buildSql();
    var results = await db.select(_sql);
    return results[0]['MAX($column)'];
  }

  /// Retrieve the minimum value of a given column.
  Future<int> min(String column) async {
    _setStatement(Operator.get);
    _setColumn(column);
    _setAggraegate(Aggregate.min);
    _buildSql();
    var results = await db.select(_sql);
    return results[0]['MIN($column)'];
  }

  /// Set the "offset" value of the query.
  QueryBuilder offset(int value) {
    _setOffset(value);
    return this;
  }

  /// Add an "order by" clause to the query.
  QueryBuilder orderBy(String column, [String direction = 'ASC']) {
    if (_orderBy == '') {
      _orderBy = '$column $direction';
    } else {
      _orderBy = '$_orderBy, $column $direction';
    }
    return this;
  }

  /// Add an "or having" clause to the query.
  QueryBuilder orHaving(String column, dynamic value, [dynamic operator]) {
    String clause = '$column = $value';
    if (value.runtimeType == String) {
      clause = "$column = '$value'";
    }
    if (operator != null) {
      clause = "$column $value $operator";
      if (operator.runtimeType == String) {
        clause = "$column $value '$operator'";
      }
    }
    if (_having == "") {
      _having = clause;
    } else {
      _having = "$_having OR $clause";
    }
    return this;
  }

  /// Add an "or where" clause to the query.
  ///
  /// If operator is not null, then value becomes operator and the operator becomes value.
  /// ```
  ///   queryBuilder.where('id', 1).orWhere('name', 'Cals');
  ///   queryBuilder.where('id', '=', 1).orWhere('name', '=', 'Cals');
  /// ```
  /// When operator is null means the default operator is equal.
  QueryBuilder orWhere(String column, dynamic value, [dynamic operator]) {
    String clause = '$column = $value';
    if (value.runtimeType == String) {
      clause = "$column = '$value'";
    }
    if (operator != null) {
      clause = "$column $value $operator";
      if (operator.runtimeType == String) {
        clause = "$column $value '$operator'";
      }
    }
    if (_where == "") {
      _where = clause;
    } else {
      _where = "$_where OR $clause";
    }
    return this;
  }

  /// Add a right join to the query.
  QueryBuilder rightJoin(String table, String key, String foreignKey) {
    _rightJoin = '$table ON ${this.table}.$key = $table.$foreignKey';
    return this;
  }

  /// Set the columns to be selected.
  QueryBuilder select([List<String>? columns]) {
    if (columns != null) {
      _columns = columns.join(', ');
    }
    return this;
  }

  /// Alias to set the "offset" value of the query.
  QueryBuilder skip(int value) {
    _setOffset(value);
    return this;
  }

  /// Execute the query and get the first result if it's the sole matching record.
  Future<Map<String, dynamic>> sole() async {
    _setStatement(Operator.get);
    _buildSql();
    var results = await db.select(_sql);
    if (results.isNotEmpty && results.length == 1) {
      return results[0];
    } else {
      return Map.of({});
    }
  }

  /// Retrieve the sum of the values of a given column.
  Future<double> sum(String column) async {
    _setStatement(Operator.get);
    _setColumn(column);
    _setAggraegate(Aggregate.sum);
    _buildSql();
    var results = await db.select(_sql);
    return results[0]['SUM($column)'];
  }

  /// Alias to set the "limit" value of the query.
  QueryBuilder take(int value) {
    _setLimit(value);
    return this;
  }

  /// Get the SQL representation of the query.
  String toSql() {
    _buildSql();
    return _sql;
  }

  /// Update records in the database.
  Future<int> update(Map<String, dynamic> value) async {
    _setStatement(Operator.update);
    _setColumns(value.keys.toList());
    _values = value.values.join(', ');
    value.forEach((String k, dynamic v) {
      if (_set == '') {
        _set = '$k = $v';
        if (v is String) {
          _set = "$k = '$v'";
        }
      } else {
        _set = '$_set, $k = $v';
        if (v is String) {
          _set = "$_set, $k = '$v'";
        }
      }
    });
    _buildSql();
    var affectedRows = await db.update(_sql);
    return affectedRows;
  }

  /// Add a basic where clause to the query.
  ///
  /// If operator is not null, then value becomes operator and the operator becomes value.
  /// ```
  ///   queryBuilder.where('id', 1);
  ///   queryBuilder.where('id', '=', 1);
  /// ```
  /// When operator is null means the default operator is equal.
  QueryBuilder where(String column, dynamic value, [dynamic operator]) {
    String clause = '$column = $value';
    if (value.runtimeType == String) {
      clause = "$column = '$value'";
    }
    if (operator != null) {
      clause = "$column $value $operator";
      if (operator.runtimeType == String) {
        clause = "$column $value '$operator'";
      }
    }
    if (_where == "") {
      _where = clause;
    } else {
      _where = "$_where AND $clause";
    }
    return this;
  }

  _buildSql() {
    switch (_statement) {
      case 'SELECT':
        String sql = '$_statement $_columns FROM $table';
        if (_leftJoin != '') {
          sql = '$sql LEFT JOIN $_leftJoin';
        }
        if (_rightJoin != '') {
          sql = '$sql RIGHT JOIN $_rightJoin';
        }
        if (_where != '') {
          sql = '$sql WHERE $_where';
        }
        if (_groupBy != '') {
          sql = '$sql GROUP BY $_groupBy';
        }
        if (_having != '') {
          sql = '$sql HAVING $_having';
        }
        if (_limit > 0) {
          sql = '$sql LIMIT $_limit';
        }
        if (_offset > 0) {
          sql = '$sql OFFSET $_offset';
        }
        if (_orderBy != '') {
          sql = '$sql ORDER BY $_orderBy';
        }
        _sql = sql
            .replaceAll(' as ', ' AS ')
            .replaceAll(' asc', ' ASC')
            .replaceAll(' desc', ' DESC');
        break;
      case 'INSERT':
        _sql = '$_statement INTO $table ($_columns) VALUES ($_values)';
        break;
      case 'UPDATE':
        String sql = '$_statement $table SET $_set';
        if (_where != '') {
          sql = '$sql WHERE $_where';
        }
        _sql = sql;
        break;
      case 'DELETE':
        String sql = '$_statement FROM $table';
        if (_where != '') {
          sql = '$sql WHERE $_where';
        }
        _sql = sql;
        break;
      default:
    }
  }

  _setAggraegate(Aggregate aggregate) {
    switch (aggregate) {
      case Aggregate.count:
        _columns = "COUNT(*)";
        break;
      case Aggregate.min:
        _columns = "MIN($_columns)";
        break;
      case Aggregate.max:
        _columns = "MAX($_columns)";
        break;
      case Aggregate.sum:
        _columns = "SUM($_columns)";
        break;
      case Aggregate.avg:
        _columns = "AVG($_columns)";
        break;
      default:
        break;
    }
  }

  _setColumn(String column) {
    _columns = column;
  }

  _setColumns(List<String> columns) {
    _columns = columns.join(', ');
  }

  _setLimit(int value) {
    _limit = value;
  }

  _setOffset(int value) {
    _offset = value;
  }

  _setStatement(Operator operator) {
    switch (operator) {
      case Operator.insert:
        _statement = 'INSERT';
        break;
      case Operator.update:
        _statement = 'UPDATE';
        break;
      case Operator.delete:
        _statement = 'DELETE';
        break;
      default:
        _statement = 'SELECT';
        break;
    }
  }
}

enum Aggregate { avg, count, max, min, sum }

enum Operator { get, insert, update, delete, first, count, min, max, sum, avg }
