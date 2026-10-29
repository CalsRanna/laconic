import 'dart:convert';
import 'dart:io';

import 'package:io/io.dart';
import 'package:path/path.dart' as p;

import 'cli_exception.dart';

String dartString(String value) => jsonEncode(value).replaceAll(r'$', r'\$');

Future<File> generateMigration({
  required Directory directory,
  required String name,
  String? createTable,
  DateTime? timestamp,
}) async {
  if (!RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$').hasMatch(name)) {
    throw FormatException('Migration names must use lower_snake_case.');
  }
  if (createTable != null &&
      !RegExp(
        r'^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?$',
      ).hasMatch(createTable)) {
    throw FormatException(
      '--create must be a table or schema.table identifier.',
    );
  }
  final now = (timestamp ?? DateTime.now()).toUtc();
  String digits(int value, int width) => value.toString().padLeft(width, '0');
  final prefix =
      '${digits(now.year, 4)}${digits(now.month, 2)}${digits(now.day, 2)}'
      '${digits(now.hour, 2)}${digits(now.minute, 2)}${digits(now.second, 2)}'
      '${digits(now.millisecond * 1000 + now.microsecond, 6)}';
  final migrationName = '${prefix}_$name';
  if (migrationName.length > 255) {
    throw FormatException(
      'The generated migration name must not exceed 255 characters.',
    );
  }
  final up =
      createTable == null
          ? "throw UnimplementedError('Implement up() before running this migration.');"
          : 'await database.schema.create(${dartString(createTable)}, (table) {\n'
              '      table.id();\n'
              '      // Add the remaining columns and constraints here.\n'
              '    });';
  final down =
      createTable == null
          ? "throw UnimplementedError('Implement down() before rolling back this migration.');"
          : 'await database.schema.drop(${dartString(createTable)});';
  final source = '''import 'package:laconic/laconic.dart';

/// Returns this file's migration for the CLI registry.
Migration migration() => _GeneratedMigration();

class _GeneratedMigration extends Migration {
  @override
  String get name => ${dartString(migrationName)};

  @override
  Future<void> up(Laconic database) async {
    $up
  }

  @override
  Future<void> down(Laconic database) async {
    $down
  }
}
''';
  await directory.create(recursive: true);
  final file = File(p.join(directory.path, '$migrationName.dart'));
  try {
    await file.create(exclusive: true);
  } on FileSystemException {
    if (await file.exists()) {
      throw MigrationCliException(
        'Migration file already exists: ${file.path}',
        ExitCode.data.code,
      );
    }
    rethrow;
  }
  try {
    await file.writeAsString(source, flush: true);
  } catch (_) {
    await file.delete();
    rethrow;
  }
  return file;
}
