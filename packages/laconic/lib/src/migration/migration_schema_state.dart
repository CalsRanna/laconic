import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../database/result.dart';
import '../exception.dart';
import '../laconic.dart';
import 'schema_state.dart';

/// Internal baseline file handling, separate from migration orchestration.
class MigrationSchemaState {
  static const _prefix = '-- Laconic schema v1 ';
  final Laconic database;
  final String table;
  final SchemaProcessRunner? runner;

  MigrationSchemaState(this.database, this.table, this.runner);

  Future<void> dump(String path, List<LaconicResult> history) async {
    final driver = database.schemaState;
    final target = File(p.absolute(path));
    if (p.extension(target.path) != '.sql') {
      throw LaconicException('Schema dumps must use a .sql file');
    }
    final parts = database.grammar.schemaTableParts(table);
    final metadata = {
      'driver': driver.schemaDialect,
      'table': table,
      'migrations': [
        for (final row in history)
          {'name': row['migration'], 'batch': row['batch']},
      ],
    };
    await target.parent.create(recursive: true);
    final temporary = await target.parent.createTemp('.laconic-schema-');
    try {
      final native = File(p.join(temporary.path, 'native.sql'));
      await driver.dumpSchema(
        native.path,
        schema: parts.length == 2 ? parts.first : null,
        runner: runner,
      );
      final output = File(p.join(temporary.path, 'schema.sql'));
      final sink = output.openWrite();
      try {
        sink.writeln('$_prefix${jsonEncode(metadata)}');
        if (driver.schemaDialect == 'sqlite') {
          sink.writeln('pragma foreign_keys = off;\nbegin transaction;');
        }
        await sink.addStream(native.openRead());
        sink.writeln();
        final grammar = database.grammar;
        for (final row in history) {
          sink.writeln(
            'insert into ${grammar.quoteSchemaIdentifier(table, qualified: true)} '
            '(${grammar.quoteSchemaIdentifier('migration')}, ${grammar.quoteSchemaIdentifier('batch')}) '
            'values (${grammar.compileSchemaLiteral(row['migration'])}, ${grammar.compileSchemaLiteral(row['batch'])});',
          );
        }
        if (driver.schemaDialect == 'sqlite') sink.writeln('commit;');
        await sink.flush();
      } finally {
        await sink.close();
      }
      await output.rename(target.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  Future<MigrationBaseline> read(String path) async {
    final sql = await File(path).readAsString();
    final end = sql.indexOf('\n');
    if (end < 0 || !sql.startsWith(_prefix)) {
      throw LaconicException('Not a Laconic schema dump: $path');
    }
    final Object? metadata = jsonDecode(sql.substring(_prefix.length, end));
    if (metadata is! Map<String, dynamic> ||
        metadata['driver'] != database.schemaState.schemaDialect ||
        metadata['table'] != table ||
        metadata['migrations'] is! List) {
      throw LaconicException(
        'Schema dump driver or history table does not match this migrator',
      );
    }
    final history = <List<Object?>>[];
    final names = <String>{};
    for (final row in metadata['migrations'] as List) {
      if (row is! Map ||
          row['name'] is! String ||
          !RegExp(r'^[A-Za-z0-9_]{1,255}$').hasMatch(row['name'] as String) ||
          row['batch'] is! int ||
          (row['batch'] as int) <= 0 ||
          !names.add((row['name'] as String).toLowerCase())) {
        throw LaconicException('Invalid migration history in schema dump');
      }
      history.add([history.length + 1, row['name'], row['batch']]);
    }
    return MigrationBaseline(
      sql,
      LaconicResult.fromRows(['id', 'migration', 'batch'], history),
    );
  }

  Future<void> load(String path) async {
    final parts = database.grammar.schemaTableParts(table);
    final schema = parts.length == 2 ? parts.first : null;
    final tables = await database.schema.getTables(schema: schema);
    final views = await database.schema.getViews(schema: schema);
    final others = tables.where((t) => t.name != parts.last);
    if (others.isNotEmpty || views.isNotEmpty) {
      throw LaconicException(
        'Schema baselines can only be loaded into an empty schema; use fresh() explicitly to rebuild',
      );
    }
    if (tables.isNotEmpty) {
      final quoted = database.grammar.quoteSchemaIdentifier(
        table,
        qualified: true,
      );
      if (await database.table(quoted).exists()) {
        throw LaconicException(
          'Cannot replace nonempty migration history with a schema baseline',
        );
      }
      await database.schema.drop(table);
    }
    await database.schemaState.loadSchema(path, schema: schema, runner: runner);
  }
}

class MigrationBaseline {
  final String sql;
  final List<LaconicResult> history;
  MigrationBaseline(this.sql, this.history);
}
