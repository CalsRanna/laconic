import 'package:laconic_mysql/src/client/exceptions.dart';
import 'package:laconic_mysql/src/client/result/result_set.dart';

class MysqlPreparedStatement {
  final int statementId;
  final int parameterCount;
  final Future<MysqlResultSet> Function(List<Object?> parameters) _execute;
  final Future<void> Function() _deallocate;

  MysqlPreparedStatement.internal({
    required this.statementId,
    required this.parameterCount,
    required Future<MysqlResultSet> Function(List<Object?> parameters) execute,
    required Future<void> Function() deallocate,
  }) : _execute = execute,
       _deallocate = deallocate;

  Future<MysqlResultSet> execute(List<Object?> parameters) {
    if (parameterCount != parameters.length) {
      throw MysqlClientException(
        'Can not execute prepared statement: '
        'number of passed parameters does not match parameterCount',
      );
    }
    return _execute(parameters);
  }

  Future<void> deallocate() => _deallocate();
}
