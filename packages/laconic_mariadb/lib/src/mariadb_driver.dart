import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';

import 'mariadb_config.dart';
import 'mariadb_grammar.dart';

/// MariaDB driver using the shared MySQL protocol and connection pool.
class MariadbDriver
    implements DatabaseDriver, MigrationLockDriver, SchemaStateDriver {
  final MariadbConfig config;
  final MysqlDriver _delegate;
  static final _grammar = MariadbGrammar();
  static const driverName = 'mariadb';

  MariadbDriver(this.config) : _delegate = _MariadbClientDriver(config);

  @override
  String get schemaDialect => 'mariadb';

  @override
  Future<void> dumpSchema(
    String path, {
    String? schema,
    SchemaProcessRunner? runner,
  }) => _run(() => _delegate.dumpSchema(path, schema: schema, runner: runner));

  @override
  Future<void> loadSchema(
    String path, {
    String? schema,
    SchemaProcessRunner? runner,
  }) => _run(() => _delegate.loadSchema(path, schema: schema, runner: runner));

  @override
  SqlGrammar get grammar => _grammar;

  LaconicException _error(Object error) {
    if (error is LaconicException) {
      if (error.driver != MysqlDriver.driverName) return error;
      return LaconicException(
        error.message,
        driver: driverName,
        code: error.code,
      );
    }
    return LaconicException(error.toString(), driver: driverName);
  }

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw _error(e);
    }
  }

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) => _run(() => _delegate.select(sql, params));

  @override
  Stream<LaconicResult> selectStream(
    String sql, [
    List<Object?> params = const [],
  ]) {
    try {
      return _delegate.selectStream(sql, params).handleError((Object e) {
        throw _error(e);
      });
    } catch (e) {
      return Stream.error(_error(e));
    }
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) =>
      _run(() => _delegate.statement(sql, params));

  @override
  Future<int> affectingStatement(
    String sql, [
    List<Object?> params = const [],
  ]) => _run(() => _delegate.affectingStatement(sql, params));

  @override
  Future<int> insertAndGetId(String sql, [List<Object?> params = const []]) =>
      _run(() => _delegate.insertAndGetId(sql, params));

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      _run(() => _delegate.transaction(action));

  @override
  Future<T> withMigrationLock<T>(Future<T> Function() action) =>
      _run(() => _delegate.withMigrationLock(action));

  @override
  Future<void> close() => _run(_delegate.close);
}

class _MariadbClientDriver extends MysqlDriver {
  _MariadbClientDriver(super.config);
  @override
  String get schemaDialect => 'mariadb';
  @override
  String get schemaDumpExecutable => 'mariadb-dump';
  @override
  String get schemaLoadExecutable => 'mariadb';
}
