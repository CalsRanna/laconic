part of 'sqlite_grammar.dart';

class _SqliteTableRebuild {
  final SqlGrammar grammar;
  final Blueprint blueprint;
  final List<SchemaColumn> columns;
  final List<Map<String, Object?>> objects;

  _SqliteTableRebuild(this.grammar, this.blueprint, this.columns, this.objects);

  List<CompiledQuery> compile() {
    final parts = grammar.schemaTableParts(blueprint.table);
    final schema = parts.length == 2 ? parts.first : 'main';
    final name = parts.last;
    final temporary = '__laconic_rebuild_$name';
    final tableObjects = objects.where(
      (o) => o['type'] == 'table' && o['name'] == name,
    );
    if (tableObjects.isEmpty) {
      throw LaconicException('Table does not exist: ${blueprint.table}');
    }
    if (objects.any((o) => o['name'] == temporary)) {
      throw LaconicException('Rebuild table already exists: $temporary');
    }
    final original = _SqliteDefinition(tableObjects.single['sql'] as String);
    final definitions = List<String>.of(original.definitions);
    final dropped = <String>{};
    final renames = <SchemaChangeCommand>[];
    final indexes = <Map<String, Object?>>[
      for (final object in objects)
        if (object['type'] == 'index' &&
            object['tbl_name'] == name &&
            object['sql'] != null)
          Map.of(object),
    ];
    final additions = <String, ColumnDefinition>{};
    for (final command in blueprint.commands) {
      if (renames.isNotEmpty &&
          !(command is SchemaChangeCommand &&
              command.change == SchemaChange.renameColumn)) {
        throw LaconicException(
          'Place renameColumn after other changes when rebuilding a SQLite table',
        );
      }
      if (command is ColumnDefinition) {
        final at = definitions.indexWhere(
          (d) => _SqliteDefinition.columnName(d) == command.name,
        );
        if (command.isChange) {
          grammar.validateChangedColumn(command);
          if (at < 0) {
            throw LaconicException('Column does not exist: ${command.name}');
          }
          if (columns.any((c) => c.name == command.name && c.generated)) {
            throw LaconicException(
              'Changing a generated column requires explicitly dropping and adding it',
            );
          }
          final column = _SqliteColumn(definitions[at]);
          final kept = column.constraints.where(
            (c) =>
                ![
                  'not',
                  'null',
                  'default',
                  if (command.collationName != null) 'collate',
                ].contains(_SqliteDefinition.constraintKind(c)),
          );
          definitions[at] =
              '${grammar.compileColumnDefinition(command)} ${kept.join(' ')}'
                  .trim();
        } else {
          if (at >= 0) {
            throw LaconicException('Column already exists: ${command.name}');
          }
          definitions.add(grammar.compileColumnDefinition(command));
          additions[command.name] = command;
          dropped.remove(command.name);
        }
      } else if (command is ForeignKeyDefinition) {
        definitions.add(grammar.compileForeignKey(command));
      } else if (command is IndexDefinition) {
        if (command.type == IndexType.primary) {
          definitions.add(
            'constraint ${grammar.quoteSchemaIdentifier(command.name)} primary key (${grammar.compileSchemaColumns(command.columns)})',
          );
        } else {
          if (indexes.any((i) => i['name'] == command.name)) {
            throw LaconicException('Index already exists: ${command.name}');
          }
          indexes.add({
            'name': command.name,
            'sql': grammar.compileSchemaIndex(blueprint.table, command).sql,
          });
        }
      } else if (command is SchemaChangeCommand) {
        switch (command.change) {
          case SchemaChange.renameColumn:
            renames.add(command);
          case SchemaChange.dropColumn:
            final at = definitions.indexWhere(
              (d) => _SqliteDefinition.columnName(d) == command.name,
            );
            if (at < 0) {
              throw LaconicException('Column does not exist: ${command.name}');
            }
            definitions.removeAt(at);
            dropped.add(command.name);
            additions.remove(command.name);
            definitions.removeWhere(
              (d) => _SqliteDefinition.isKeyOn(d, command.name),
            );
            indexes.removeWhere(
              (i) => _SqliteDefinition.references(
                i['sql'] as String,
                command.name,
              ),
            );
          case SchemaChange.dropIndex:
            final at = indexes.indexWhere((i) => i['name'] == command.name);
            if (at < 0) {
              throw LaconicException(
                'Explicit index does not exist: ${command.name}',
              );
            }
            indexes.removeAt(at);
          case SchemaChange.renameIndex:
            renameIndex(grammar, blueprint.table, indexes, command);
          case SchemaChange.dropFullText:
            throw LaconicException(
              'SQLite full-text search requires an FTS virtual table; dropFullText() is not supported',
            );
          case SchemaChange.dropPrimary:
            final at = definitions.indexWhere(
              (d) =>
                  _SqliteDefinition.columnName(d) == null &&
                  _SqliteDefinition.constraintKind(d) == 'primary' &&
                  _SqliteDefinition.constraintName(d) == command.name,
            );
            if (at < 0) {
              throw LaconicException(
                'Named primary key does not exist: ${command.name}',
              );
            }
            if (_SqliteDefinition.hasKeyword(original.suffix, 'without')) {
              throw LaconicException(
                'Cannot drop the primary key of a WITHOUT ROWID table',
              );
            }
            definitions.removeAt(at);
          case SchemaChange.dropForeign:
            var found = false;
            for (var i = definitions.length - 1; i >= 0; i--) {
              final definition = definitions[i];
              if (_SqliteDefinition.columnName(definition) == null) {
                if (_SqliteDefinition.constraintName(definition) ==
                        command.name &&
                    _SqliteDefinition.constraintKind(definition) == 'foreign') {
                  definitions.removeAt(i);
                  found = true;
                }
              } else {
                final column = _SqliteColumn(definition);
                final kept =
                    column.constraints.where((c) {
                      final matches =
                          _SqliteDefinition.constraintName(c) == command.name &&
                          _SqliteDefinition.constraintKind(c) == 'references';
                      if (matches) found = true;
                      return !matches;
                    }).toList();
                definitions[i] = '${column.prefix} ${kept.join(' ')}'.trim();
              }
            }
            if (!found) {
              throw LaconicException(
                'Named foreign key does not exist: ${command.name}',
              );
            }
        }
      }
    }
    for (final column in dropped) {
      if (definitions.any((d) => _SqliteDefinition.references(d, column))) {
        throw LaconicException(
          'Dropped column $column is used by a preserved constraint or generated column',
        );
      }
      for (final object in objects.where(
        (o) => o['type'] == 'trigger' || o['type'] == 'view',
      )) {
        final sql = object['sql'] as String?;
        if (sql != null &&
            _SqliteDefinition.references(sql, name) &&
            _SqliteDefinition.references(sql, column)) {
          throw LaconicException(
            'Dropped column $column is used by ${object['type']} ${object['name']}',
          );
        }
      }
    }
    final names =
        definitions
            .map(_SqliteDefinition.columnName)
            .whereType<String>()
            .toList();
    if (names.isEmpty) {
      throw LaconicException('A table requires at least one column');
    }
    final renamedNames = names.toSet();
    for (final rename in renames) {
      if (!renamedNames.remove(rename.name) ||
          !renamedNames.add(rename.newName!)) {
        throw LaconicException(
          'Invalid column rename: ${rename.name} to ${rename.newName}',
        );
      }
    }
    final sourceColumns = {for (final column in columns) column.name: column};
    final targets = <String>[];
    final sources = <String>[];
    for (final column in names) {
      final definition = definitions.singleWhere(
        (d) => _SqliteDefinition.columnName(d) == column,
      );
      if (_SqliteColumn(definition).constraints.any(
        (c) => const [
          'generated',
          'as',
        ].contains(_SqliteDefinition.constraintKind(c)),
      )) {
        continue;
      }
      targets.add(grammar.quoteSchemaIdentifier(column));
      if (sourceColumns.containsKey(column) && !additions.containsKey(column)) {
        sources.add(grammar.quoteSchemaIdentifier(column));
      } else {
        final added = additions[column]!;
        sources.add(
          added.hasDefault ? grammar.compileColumnDefault(added) : 'null',
        );
      }
    }
    // Preserve observable rowids, including tables without an INTEGER PRIMARY KEY.
    final withoutRowid = original.suffix.toUpperCase().contains(
      'WITHOUT ROWID',
    );
    if (!withoutRowid &&
        !columns.any((c) => c.autoIncrement && names.contains(c.name))) {
      final aliases = [
        'rowid',
        '_rowid_',
        'oid',
      ].where((a) => !sourceColumns.containsKey(a) && !names.contains(a));
      if (aliases.isNotEmpty) {
        targets.insert(0, grammar.quoteSchemaIdentifier(aliases.first));
        sources.insert(0, grammar.quoteSchemaIdentifier(aliases.first));
      }
    }
    final target =
        '${grammar.quoteSchemaIdentifier(schema)}.${grammar.quoteSchemaIdentifier(name)}';
    final temp =
        '${grammar.quoteSchemaIdentifier(schema)}.${grammar.quoteSchemaIdentifier(temporary)}';
    final statements = <String>[
      'create table $temp (${definitions.join('\n, ')})${original.suffix}',
      'insert into $temp (${targets.join(', ')}) select ${sources.join(', ')} from $target',
    ];
    if (_SqliteDefinition.hasKeyword(original.sql, 'autoincrement') &&
        definitions.any(
          (d) => _SqliteDefinition.hasKeyword(d, 'autoincrement'),
        )) {
      final sequence =
          '${grammar.quoteSchemaIdentifier(schema)}.sqlite_sequence';
      final oldName = grammar.compileSchemaLiteral(name);
      final newName = grammar.compileSchemaLiteral(temporary);
      statements.add(
        'insert into $sequence(name, seq) select $newName, seq from $sequence where name = $oldName and not exists (select 1 from $sequence where name = $newName)',
      );
      statements.add(
        'update $sequence set seq = max(seq, coalesce((select seq from $sequence where name = $oldName), 0)) where name = $newName',
      );
    }
    statements.addAll([
      'drop table $target',
      'alter table $temp rename to ${grammar.quoteSchemaIdentifier(name)}',
    ]);
    statements.addAll(
      indexes.map((i) => _qualifyObject(i['sql'] as String, schema, 'index')),
    );
    statements.addAll(
      objects
          .where(
            (o) =>
                o['type'] == 'trigger' &&
                o['tbl_name'] == name &&
                o['sql'] != null,
          )
          .map((o) => _qualifyObject(o['sql'] as String, schema, 'trigger')),
    );
    statements.addAll(
      renames.map(
        (rename) => grammar.compileSchemaChange(blueprint.table, rename).sql,
      ),
    );
    return statements
        .map((sql) => CompiledQuery(sql: sql, bindings: []))
        .toList();
  }

  static String renameIndex(
    SqlGrammar grammar,
    String table,
    List<Map<String, Object?>> indexes,
    SchemaChangeCommand command,
  ) {
    final matches = indexes.where((i) => i['name'] == command.name);
    if (matches.length != 1 ||
        indexes.any((i) => i['name'] == command.newName)) {
      throw LaconicException(
        'Cannot rename explicit index ${command.name} to ${command.newName}',
      );
    }
    final index = matches.single;
    final sql = index['sql'] as String;
    final tokens = _SqliteDefinition.tokens(sql);
    var at = tokens.indexWhere((t) => t.keyword == 'index') + 1;
    if (tokens[at].keyword == 'if') at += 3;
    var end = tokens[at].end;
    if (tokens[at + 1].value == '.') end = tokens[at + 2].end;
    final parts = grammar.schemaTableParts(table);
    final prefix =
        parts.length == 2
            ? '${grammar.quoteSchemaIdentifier(parts.first)}.'
            : '';
    final renamed = sql.replaceRange(
      tokens[at].start,
      end,
      '$prefix${grammar.quoteSchemaIdentifier(command.newName!)}',
    );
    index['name'] = command.newName;
    index['sql'] = renamed;
    return renamed;
  }

  String _qualifyObject(String sql, String schema, String kind) {
    final tokens = _SqliteDefinition.tokens(sql);
    var at = tokens.indexWhere((t) => t.keyword == kind) + 1;
    if (tokens[at].keyword == 'if') at += 3;
    var end = tokens[at].end;
    var name = tokens[at].value;
    if (at + 2 < tokens.length && tokens[at + 1].value == '.') {
      end = tokens[at + 2].end;
      name = tokens[at + 2].value;
    }
    return sql.replaceRange(
      tokens[at].start,
      end,
      '${grammar.quoteSchemaIdentifier(schema)}.${grammar.quoteSchemaIdentifier(name)}',
    );
  }
}

class _SqliteColumn {
  final String prefix;
  final List<String> constraints;

  _SqliteColumn._(this.prefix, this.constraints);

  factory _SqliteColumn(String sql) {
    final tokens = _SqliteDefinition.tokens(sql);
    final starts = <int>[];
    const kinds = {
      'constraint',
      'primary',
      'not',
      'null',
      'unique',
      'check',
      'default',
      'collate',
      'references',
      'generated',
      'as',
    };
    var kind = '';
    var startToken = -1;
    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.depth != 0 || !kinds.contains(token.keyword)) continue;
      final previous = tokens[i - 1].keyword;
      if (kind == 'constraint' && i == startToken + 2) {
        kind = token.keyword;
        continue;
      }
      if (token.keyword == 'null' &&
          (previous == 'not' || previous == 'default' || previous == 'set')) {
        continue;
      }
      if (token.keyword == 'default' && previous == 'set') continue;
      if (token.keyword == 'as' && kind == 'generated') continue;
      starts.add(token.start);
      kind = token.keyword;
      startToken = i;
    }
    return _SqliteColumn._(
      sql.substring(0, starts.isEmpty ? sql.length : starts.first).trim(),
      [
        for (var i = 0; i < starts.length; i++)
          sql
              .substring(
                starts[i],
                i + 1 < starts.length ? starts[i + 1] : sql.length,
              )
              .trim(),
      ],
    );
  }
}

class _SqliteDefinition {
  final String sql;
  late final List<String> definitions;
  late final String suffix;

  _SqliteDefinition(this.sql) {
    final parsed = tokens(sql);
    final open = parsed.indexWhere((t) => t.value == '(');
    if (open < 0) {
      throw LaconicException('Cannot parse SQLite table definition');
    }
    if (parsed.take(open).any((t) => t.keyword == 'virtual')) {
      throw LaconicException('SQLite virtual tables cannot be rebuilt');
    }
    final close = parsed.indexWhere((t) => t.value == ')' && t.depth == 0);
    if (close < 0) {
      throw LaconicException('Cannot parse SQLite table definition');
    }
    final separators = parsed
        .sublist(open + 1, close)
        .where((t) => t.value == ',' && t.depth == 1);
    definitions = [];
    var start = parsed[open].end;
    for (final separator in separators) {
      definitions.add(sql.substring(start, separator.start).trim());
      start = separator.end;
    }
    definitions.add(sql.substring(start, parsed[close].start).trim());
    suffix = sql
        .substring(parsed[close].end)
        .replaceFirst(RegExp(r';\s*$'), '');
  }

  static String? columnName(String sql) {
    final first = tokens(sql).first;
    return const [
          'constraint',
          'primary',
          'unique',
          'check',
          'foreign',
        ].contains(first.keyword)
        ? null
        : first.value;
  }

  static String constraintKind(String sql) {
    final parts = tokens(sql);
    return parts[parts.first.keyword == 'constraint' ? 2 : 0].keyword;
  }

  static String? constraintName(String sql) {
    final parts = tokens(sql);
    return parts.first.keyword == 'constraint' ? parts[1].value : null;
  }

  static bool isKeyOn(String sql, String column) {
    if (columnName(sql) != null ||
        !const ['primary', 'unique', 'foreign'].contains(constraintKind(sql))) {
      return false;
    }
    final parsed = tokens(sql);
    final start = parsed.indexWhere((t) => t.value == '(');
    final end = parsed.indexWhere((t) => t.value == ')' && t.depth == 0);
    return parsed
        .sublist(start + 1, end)
        .any((t) => t.value.toLowerCase() == column.toLowerCase());
  }

  static bool references(String sql, String name) => tokens(
    sql,
  ).any((t) => !t.literal && t.value.toLowerCase() == name.toLowerCase());
  static bool hasKeyword(String sql, String keyword) =>
      tokens(sql).any((t) => t.keyword == keyword);

  static List<_SqliteToken> tokens(String sql) {
    final result = <_SqliteToken>[];
    var i = 0;
    var depth = 0;
    while (i < sql.length) {
      if (sql[i].trim().isEmpty) {
        i++;
        continue;
      }
      if (sql.startsWith('--', i)) {
        final end = sql.indexOf('\n', i + 2);
        i = end < 0 ? sql.length : end + 1;
        continue;
      }
      if (sql.startsWith('/*', i)) {
        final end = sql.indexOf('*/', i + 2);
        if (end < 0) throw LaconicException('Unterminated SQLite SQL comment');
        i = end + 2;
        continue;
      }
      final start = i;
      final char = sql[i];
      if ('\'"`['.contains(char)) {
        final quote = char == '[' ? ']' : char;
        final value = StringBuffer();
        i++;
        var closed = false;
        while (i < sql.length) {
          if (sql[i] == quote) {
            if (i + 1 < sql.length && sql[i + 1] == quote) {
              value.write(quote);
              i += 2;
            } else {
              i++;
              closed = true;
              break;
            }
          } else {
            value.write(sql[i++]);
          }
        }
        if (!closed) throw LaconicException('Unterminated SQLite SQL quote');
        result.add(
          _SqliteToken(
            start,
            i,
            value.toString(),
            depth,
            quoted: true,
            literal: char == "'",
          ),
        );
      } else if (RegExp(r'[\w\u0080-\uffff]').hasMatch(char)) {
        i++;
        while (i < sql.length &&
            RegExp(r'[\w\u0080-\uffff$]').hasMatch(sql[i])) {
          i++;
        }
        result.add(_SqliteToken(start, i, sql.substring(start, i), depth));
      } else {
        if (char == ')') depth--;
        result.add(_SqliteToken(start, ++i, char, depth, quoted: true));
        if (char == '(') depth++;
      }
    }
    return result;
  }
}

class _SqliteToken {
  final int start;
  final int end;
  final String value;
  final int depth;
  final bool quoted;
  final bool literal;
  const _SqliteToken(
    this.start,
    this.end,
    this.value,
    this.depth, {
    this.quoted = false,
    this.literal = false,
  });
  String get keyword => quoted ? '' : value.toLowerCase();
}
