import '../database/database_driver.dart';
import '../database/query.dart';
import '../database/result.dart';
import '../grammar/grammar.dart';
import '../laconic.dart';
import '../schema/schema_builder.dart';

// Migration SQL is captured without executing it, even when a SELECT contains
// DML/RETURNING or the migration explicitly opens a transaction. Only the schema
// builder's grammar-generated metadata queries use the live connection.
class MigrationPreviewDatabase extends Laconic {
  late final SchemaBuilder _schema;

  @override
  SchemaBuilder get schema => _schema;

  MigrationPreviewDatabase(Laconic source, void Function(LaconicQuery) onQuery)
    : super(_PreviewDriver(source.grammar, onQuery)) {
    _schema = SchemaBuilder(this, metadataDatabase: source);
  }
}

class _PreviewDriver extends DatabaseDriver implements SchemaTransactionDriver {
  @override
  final SqlGrammar grammar;
  final void Function(LaconicQuery) onQuery;

  _PreviewDriver(this.grammar, this.onQuery);

  void _record(String sql, List<Object?> params) =>
      onQuery(LaconicQuery(sql: sql, bindings: List.unmodifiable(params)));

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    _record(sql, params);
    return [];
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async =>
      _record(sql, params);

  @override
  Future<int> affectingStatement(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    _record(sql, params);
    return 0;
  }

  @override
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    _record(sql, params);
    return 0;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) => action();

  @override
  Future<T> schemaTransaction<T>(Future<T> Function() action) => action();

  @override
  Future<void> close() async {}
}
