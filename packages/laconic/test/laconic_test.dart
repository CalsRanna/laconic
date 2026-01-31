import 'package:laconic/laconic.dart';
import 'package:test/test.dart';

/// A simple Grammar implementation for testing core package functionality.
class MockGrammar extends Grammar {
  @override
  CompiledQuery compileSelect({
    required String table,
    required List<String> columns,
    required List<Map<String, dynamic>> wheres,
    required List<Map<String, dynamic>> joins,
    required List<Map<String, dynamic>> orders,
    required List<String> groups,
    required List<Map<String, dynamic>> havings,
    required bool distinct,
    int? limit,
    int? offset,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('select ');
    if (distinct) buffer.write('distinct ');
    buffer.write(columns.isEmpty || (columns.length == 1 && columns[0] == '*')
        ? '*'
        : columns.join(', '));
    buffer.write(' from $table');

    if (joins.isNotEmpty) {
      for (final join in joins) {
        final type = join['type'] as String? ?? 'inner';
        final joinTable = join['table'] as String;
        final conditions = join['conditions'] as List<Map<String, dynamic>>;
        if (type == 'left') {
          buffer.write(' left join $joinTable');
        } else if (type == 'cross') {
          buffer.write(' cross join $joinTable');
        } else {
          buffer.write(' join $joinTable');
        }
        if (conditions.isNotEmpty) {
          buffer.write(' on ');
          for (var i = 0; i < conditions.length; i++) {
            final c = conditions[i];
            if (i > 0) buffer.write(' ${c['boolean']} ');
            buffer.write('${c['left']} ${c['operator']} ${c['right']}');
          }
        }
      }
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      for (var i = 0; i < wheres.length; i++) {
        final w = wheres[i];
        if (i > 0) buffer.write(' ${w['boolean']} ');
        final type = w['type'];
        if (type == 'basic') {
          buffer.write('${w['column']} ${w['operator']} ?');
          bindings.add(w['value']);
        } else if (type == 'in') {
          final values = w['values'] as List<Object?>;
          final not = w['not'] as bool;
          if (values.isEmpty) {
            buffer.write(not ? '1 = 1' : '1 = 0');
          } else {
            final placeholders = List.filled(values.length, '?').join(', ');
            buffer.write(
                '${w['column']} ${not ? 'not in' : 'in'} ($placeholders)');
            bindings.addAll(values);
          }
        } else if (type == 'null') {
          final not = w['not'] as bool;
          buffer.write('${w['column']} ${not ? 'is not null' : 'is null'}');
        }
      }
    }

    if (orders.isNotEmpty) {
      buffer.write(' order by ');
      buffer.write(
          orders.map((o) => '${o['column']} ${o['direction']}').join(', '));
    }

    if (limit != null) {
      buffer.write(' limit ?');
      bindings.add(limit);
    }

    if (offset != null) {
      buffer.write(' offset ?');
      bindings.add(offset);
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileInsert({
    required String table,
    required List<Map<String, Object?>> data,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];
    final columns = data.first.keys.toList();

    buffer.write('insert into $table (');
    buffer.write(columns.join(', '));
    buffer.write(') values ');

    for (var i = 0; i < data.length; i++) {
      buffer.write('(');
      final row = data[i];
      for (var j = 0; j < columns.length; j++) {
        buffer.write('?');
        bindings.add(row[columns[j]]);
        if (j < columns.length - 1) buffer.write(', ');
      }
      buffer.write(')');
      if (i < data.length - 1) buffer.write(', ');
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileUpdate({
    required String table,
    required Map<String, Object?> data,
    required List<Map<String, dynamic>> wheres,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('update $table set ');
    final entries = data.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      buffer.write('${entries[i].key} = ?');
      bindings.add(entries[i].value);
      if (i < entries.length - 1) buffer.write(', ');
    }

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      for (var i = 0; i < wheres.length; i++) {
        final w = wheres[i];
        if (i > 0) buffer.write(' ${w['boolean']} ');
        buffer.write('${w['column']} ${w['operator']} ?');
        bindings.add(w['value']);
      }
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileDelete({
    required String table,
    required List<Map<String, dynamic>> wheres,
  }) {
    final buffer = StringBuffer();
    final bindings = <Object?>[];

    buffer.write('delete from $table');

    if (wheres.isNotEmpty) {
      buffer.write(' where ');
      for (var i = 0; i < wheres.length; i++) {
        final w = wheres[i];
        if (i > 0) buffer.write(' ${w['boolean']} ');
        buffer.write('${w['column']} ${w['operator']} ?');
        bindings.add(w['value']);
      }
    }

    return CompiledQuery(sql: buffer.toString(), bindings: bindings);
  }

  @override
  CompiledQuery compileInsertGetId({
    required String table,
    required Map<String, Object?> data,
    String idColumn = 'id',
  }) {
    return compileInsert(table: table, data: [data]);
  }
}

/// Mock driver for testing the core package without database dependencies.
class MockDriver implements LaconicDriver {
  final List<String> executedSql = [];
  final List<List<Object?>> executedParams = [];
  List<Map<String, Object?>> mockResults = [];

  @override
  Grammar get grammar => MockGrammar();

  @override
  Future<List<LaconicResult>> select(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    executedSql.add(sql);
    executedParams.add(params);
    return mockResults.map((r) => LaconicResult.fromMap(r)).toList();
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    executedSql.add(sql);
    executedParams.add(params);
  }

  @override
  Future<int> insertAndGetId(
    String sql, [
    List<Object?> params = const [],
  ]) async {
    executedSql.add(sql);
    executedParams.add(params);
    return 1;
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    return await action();
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('Laconic Core:', () {
    late MockDriver driver;
    late Laconic laconic;

    setUp(() {
      driver = MockDriver();
      laconic = Laconic(driver);
    });

    test('table() creates QueryBuilder', () {
      final builder = laconic.table('users');
      expect(builder, isA<QueryBuilder>());
    });

    test('grammar is exposed from driver', () {
      expect(laconic.grammar, isA<MockGrammar>());
    });

    test('select query is compiled correctly', () async {
      driver.mockResults = [
        {'id': 1, 'name': 'John'},
      ];

      final results = await laconic.table('users').where('id', 1).get();

      expect(results.length, 1);
      expect(results.first['name'], 'John');
      expect(driver.executedSql.first, 'select * from users where id = ?');
      expect(driver.executedParams.first, [1]);
    });

    test('insert query is compiled correctly', () async {
      await laconic.table('users').insert([
        {'name': 'John', 'age': 25},
      ]);

      expect(
        driver.executedSql.first,
        'insert into users (name, age) values (?, ?)',
      );
      expect(driver.executedParams.first, ['John', 25]);
    });

    test('update query is compiled correctly', () async {
      await laconic.table('users').where('id', 1).update({'name': 'Jane'});

      expect(
        driver.executedSql.first,
        'update users set name = ? where id = ?',
      );
      expect(driver.executedParams.first, ['Jane', 1]);
    });

    test('delete query is compiled correctly', () async {
      await laconic.table('users').where('id', 1).delete();

      expect(driver.executedSql.first, 'delete from users where id = ?');
      expect(driver.executedParams.first, [1]);
    });

    test('whereIn compiles correctly', () async {
      await laconic.table('users').whereIn('id', [1, 2, 3]).get();

      expect(
        driver.executedSql.first,
        'select * from users where id in (?, ?, ?)',
      );
      expect(driver.executedParams.first, [1, 2, 3]);
    });

    test('whereNull compiles correctly', () async {
      await laconic.table('users').whereNull('deleted_at').get();

      expect(
        driver.executedSql.first,
        'select * from users where deleted_at is null',
      );
      expect(driver.executedParams.first, isEmpty);
    });

    test('join compiles correctly', () async {
      await laconic
          .table('users u')
          .select(['u.name', 'p.title'])
          .join('posts p', (join) => join.on('u.id', 'p.user_id'))
          .get();

      expect(
        driver.executedSql.first,
        'select u.name, p.title from users u join posts p on u.id = p.user_id',
      );
    });

    test('listen callback is called', () async {
      final queries = <LaconicQuery>[];
      final listeningLaconic = Laconic(driver, listen: (q) => queries.add(q));

      await listeningLaconic.table('users').get();

      expect(queries.length, 1);
      expect(queries.first.sql, 'select * from users');
    });
  });

  group('LaconicResult:', () {
    test('operator[] returns value by column name', () {
      final result = LaconicResult.fromMap({'id': 1, 'name': 'John'});
      expect(result['id'], 1);
      expect(result['name'], 'John');
    });

    test('operator[] throws for unknown column', () {
      final result = LaconicResult.fromMap({'id': 1});
      expect(() => result['unknown'], throwsArgumentError);
    });

    test('toMap returns column-value map', () {
      final result = LaconicResult.fromMap({'id': 1, 'name': 'John'});
      expect(result.toMap(), {'id': 1, 'name': 'John'});
    });
  });
}
