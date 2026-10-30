import '../exception.dart';
import 'schema_command.dart';

/// Collects ordered commands for creating or altering a table.
class Blueprint {
  /// The unquoted table name, optionally qualified by a schema.
  final String table;
  final List<SchemaCommand> _commands = [];

  /// Creates a definition for [table].
  Blueprint(this.table);

  /// The commands in declaration order.
  List<SchemaCommand> get commands => List.unmodifiable(_commands);

  /// Adds a generated integer primary key.
  ///
  /// Uses a signed BIGINT on server databases and INTEGER on SQLite.
  ColumnDefinition id([String name = 'id']) =>
      _column(name, ColumnType.bigInteger, autoIncrement: true).primary();

  /// Adds an auto-incrementing integer primary key.
  ColumnDefinition increments(String name) =>
      _column(name, ColumnType.integer, autoIncrement: true).primary();

  /// Adds an auto-incrementing BIGINT primary key, matching [id].
  ColumnDefinition bigIncrements(String name) => id(name);

  /// Adds an auto-incrementing small integer primary key.
  ColumnDefinition smallIncrements(String name) =>
      _column(name, ColumnType.smallInteger, autoIncrement: true).primary();

  /// Adds an auto-incrementing tiny integer primary key.
  ColumnDefinition tinyIncrements(String name) =>
      _column(name, ColumnType.tinyInteger, autoIncrement: true).primary();

  /// Adds an auto-incrementing medium integer primary key.
  ColumnDefinition mediumIncrements(String name) =>
      _column(name, ColumnType.mediumInteger, autoIncrement: true).primary();

  /// Adds a tiny integer using the database's supported integer range.
  ColumnDefinition tinyInteger(String name) =>
      _column(name, ColumnType.tinyInteger);

  /// Adds a small integer column.
  ColumnDefinition smallInteger(String name) =>
      _column(name, ColumnType.smallInteger);

  /// Adds a medium integer, or an ordinary integer when no medium type exists.
  ColumnDefinition mediumInteger(String name) =>
      _column(name, ColumnType.mediumInteger);

  /// Adds an unsigned integer on MySQL or MariaDB.
  ColumnDefinition unsignedInteger(String name) => integer(name).unsigned();

  /// Adds an unsigned BIGINT on MySQL or MariaDB.
  ColumnDefinition unsignedBigInteger(String name) =>
      bigInteger(name).unsigned();

  /// Adds an unsigned tiny integer on MySQL or MariaDB.
  ColumnDefinition unsignedTinyInteger(String name) =>
      tinyInteger(name).unsigned();

  /// Adds an unsigned small integer on MySQL or MariaDB.
  ColumnDefinition unsignedSmallInteger(String name) =>
      smallInteger(name).unsigned();

  /// Adds an unsigned medium integer on MySQL or MariaDB.
  ColumnDefinition unsignedMediumInteger(String name) =>
      mediumInteger(name).unsigned();

  /// Adds an integer column.
  ColumnDefinition integer(String name) => _column(name, ColumnType.integer);

  /// Adds a signed 64-bit integer column.
  ColumnDefinition bigInteger(String name) =>
      _column(name, ColumnType.bigInteger);

  /// Adds a string column with a maximum [length].
  ColumnDefinition string(String name, {int length = 255}) {
    if (length <= 0) throw LaconicException('String length must be positive');
    return _column(name, ColumnType.string, length: length);
  }

  /// Adds a text column.
  ColumnDefinition text(String name) => _column(name, ColumnType.text);

  /// Adds fixed-width character storage where supported by the database.
  ColumnDefinition char(String name, {int length = 255}) =>
      _column(name, ColumnType.char, length: length);

  /// Adds tiny text, or ordinary text where no tiny type exists.
  ColumnDefinition tinyText(String name) => _column(name, ColumnType.tinyText);

  /// Adds medium text, or ordinary text where no medium type exists.
  ColumnDefinition mediumText(String name) =>
      _column(name, ColumnType.mediumText);

  /// Adds long text, or ordinary text where no long type exists.
  ColumnDefinition longText(String name) => _column(name, ColumnType.longText);

  /// Adds a boolean column.
  ColumnDefinition boolean(String name) => _column(name, ColumnType.boolean);

  /// Adds a decimal column with [precision] digits and [scale] fractional digits.
  ColumnDefinition decimal(String name, {int precision = 10, int scale = 2}) {
    if (precision <= 0 || scale < 0 || scale > precision) {
      throw LaconicException('Invalid decimal precision or scale');
    }
    return _column(
      name,
      ColumnType.decimal,
      precision: precision,
      scale: scale,
    );
  }

  /// Adds a double-precision floating point column.
  ColumnDefinition doublePrecision(String name) =>
      _column(name, ColumnType.doublePrecision);

  /// Adds floating-point storage with a binary precision from 1 to 53.
  ColumnDefinition float(String name, {int precision = 53}) =>
      _column(name, ColumnType.float, precision: precision);

  /// Adds a date column.
  ColumnDefinition date(String name) => _column(name, ColumnType.date);

  /// Adds a date and time column without an implicit timezone conversion.
  ColumnDefinition dateTime(String name, {int? precision}) =>
      _column(name, ColumnType.dateTime, precision: precision);

  /// Adds a timestamp column using the database's timestamp semantics.
  ColumnDefinition timestamp(String name, {int? precision}) =>
      _column(name, ColumnType.timestamp, precision: precision);

  /// Adds a timezone-aware date-time where supported, or rejects it.
  ColumnDefinition dateTimeTz(String name, {int? precision}) =>
      _column(name, ColumnType.dateTimeTz, precision: precision);

  /// Adds a timezone-aware timestamp where supported, or rejects it.
  ColumnDefinition timestampTz(String name, {int? precision}) =>
      _column(name, ColumnType.timestampTz, precision: precision);

  /// Adds a time column with optional fractional-second precision.
  ColumnDefinition time(String name, {int? precision}) =>
      _column(name, ColumnType.time, precision: precision);

  /// Adds a timezone-aware time where supported, or rejects it.
  ColumnDefinition timeTz(String name, {int? precision}) =>
      _column(name, ColumnType.timeTz, precision: precision);

  /// Adds a native year or integer year column, depending on the database.
  ColumnDefinition year(String name) => _column(name, ColumnType.year);

  /// Adds nullable `created_at` and `updated_at` timestamp columns.
  void timestamps({int? precision}) {
    timestamp('created_at', precision: precision).nullable();
    timestamp('updated_at', precision: precision).nullable();
  }

  /// Adds nullable timezone-aware creation and update timestamps.
  void timestampsTz({int? precision}) {
    timestampTz('created_at', precision: precision).nullable();
    timestampTz('updated_at', precision: precision).nullable();
  }

  /// Adds nullable timestamps, matching [timestamps].
  void nullableTimestamps({int? precision}) => timestamps(precision: precision);

  /// Adds a nullable soft-deletion timestamp without changing query behavior.
  ColumnDefinition softDeletes({String name = 'deleted_at', int? precision}) =>
      timestamp(name, precision: precision).nullable();

  /// Adds a nullable timezone-aware soft-deletion timestamp.
  ColumnDefinition softDeletesTz({
    String name = 'deleted_at',
    int? precision,
  }) => timestampTz(name, precision: precision).nullable();

  /// Adds a nullable 100-character authentication token column.
  ColumnDefinition rememberToken() =>
      string('remember_token', length: 100).nullable();

  /// Adds a binary column.
  ColumnDefinition binary(String name, {int? length, bool fixed = false}) =>
      _column(name, ColumnType.binary, length: length, fixed: fixed);

  /// Adds a JSON column using the database's native or text representation.
  ColumnDefinition json(String name) => _column(name, ColumnType.json);

  /// Adds JSONB on PostgreSQL, or the driver's ordinary JSON representation.
  ColumnDefinition jsonb(String name) => _column(name, ColumnType.jsonb);

  /// Adds a UUID column using the database's native or string representation.
  ColumnDefinition uuid(String name) => _column(name, ColumnType.uuid);

  /// Adds storage for a 26-character ULID; values are supplied by the caller.
  ColumnDefinition ulid(String name) => _column(name, ColumnType.ulid);

  /// Adds a native enumeration or a string with a CHECK constraint.
  ColumnDefinition enumColumn(String name, List<String> allowed) =>
      _column(name, ColumnType.enumeration, allowed: allowed);

  /// Adds a native SET column on MySQL or MariaDB.
  ColumnDefinition set(String name, List<String> allowed) =>
      _column(name, ColumnType.set, allowed: allowed);

  /// Adds native PostgreSQL INET or 45-character IP address storage.
  ColumnDefinition ipAddress(String name) =>
      _column(name, ColumnType.ipAddress);

  /// Adds native PostgreSQL MACADDR or 17-character MAC address storage.
  ColumnDefinition macAddress(String name) =>
      _column(name, ColumnType.macAddress);

  /// Adds native geometry storage; PostgreSQL requires PostGIS.
  ColumnDefinition geometry(String name) => _column(name, ColumnType.geometry);

  /// Adds native geography storage on PostgreSQL/PostGIS or SQL Server.
  ColumnDefinition geography(String name) =>
      _column(name, ColumnType.geography);

  /// Adds a SQL Server computed column using trusted, unbound SQL.
  ///
  /// Its type and nullability are inferred by SQL Server. Use `persisted()`
  /// to store the value, optionally with `nullable(false)` to enforce NOT NULL.
  ColumnDefinition computed(String name, String expression) =>
      _column(name, ColumnType.computed).virtualAs(expression).nullable();

  /// Adds a BIGINT foreign-key column matching the signed [id] convention.
  ForeignIdColumnDefinition foreignId(String name) =>
      _foreignColumn(name, ColumnType.bigInteger);

  /// Adds a UUID foreign-key column.
  ForeignIdColumnDefinition foreignUuid(String name) =>
      _foreignColumn(name, ColumnType.uuid);

  /// Adds a ULID foreign-key column.
  ForeignIdColumnDefinition foreignUlid(String name) =>
      _foreignColumn(name, ColumnType.ulid);

  /// Adds type and BIGINT ID columns with a compound index.
  void morphs(String name, {String? indexName}) =>
      _morphs(name, ColumnType.bigInteger, false, indexName);

  /// Adds nullable type and BIGINT ID columns with a compound index.
  void nullableMorphs(String name, {String? indexName}) =>
      _morphs(name, ColumnType.bigInteger, true, indexName);

  /// Adds type and UUID columns with a compound index.
  void uuidMorphs(String name, {String? indexName}) =>
      _morphs(name, ColumnType.uuid, false, indexName);

  /// Adds nullable type and UUID columns with a compound index.
  void nullableUuidMorphs(String name, {String? indexName}) =>
      _morphs(name, ColumnType.uuid, true, indexName);

  /// Adds type and ULID columns with a compound index.
  void ulidMorphs(String name, {String? indexName}) =>
      _morphs(name, ColumnType.ulid, false, indexName);

  /// Adds nullable type and ULID columns with a compound index.
  void nullableUlidMorphs(String name, {String? indexName}) =>
      _morphs(name, ColumnType.ulid, true, indexName);

  /// Drops the creation and update timestamp columns.
  void dropTimestamps() {
    dropColumn('created_at');
    dropColumn('updated_at');
  }

  /// Drops timezone-aware creation and update timestamp columns.
  void dropTimestampsTz() => dropTimestamps();

  /// Drops the soft-deletion column.
  void dropSoftDeletes({String name = 'deleted_at'}) => dropColumn(name);

  /// Drops the timezone-aware soft-deletion column.
  void dropSoftDeletesTz({String name = 'deleted_at'}) => dropColumn(name);

  /// Drops the authentication token column.
  void dropRememberToken() => dropColumn('remember_token');

  /// Drops a polymorphic index and its type/ID columns.
  void dropMorphs(String name, {String? indexName}) {
    dropIndex(indexName ?? _name(['${name}_type', '${name}_id'], 'index'));
    dropColumn('${name}_type');
    dropColumn('${name}_id');
  }

  /// Drops a foreign-key constraint before dropping its column.
  void dropConstrainedForeignId(String name, {String? constraintName}) {
    dropForeign(constraintName ?? _name([name], 'foreign'));
    dropColumn(name);
  }

  /// Adds a named non-unique index.
  IndexDefinition index(List<String> columns, {String? name}) =>
      _index(columns, IndexType.normal, name);

  /// Adds a named unique index.
  IndexDefinition unique(List<String> columns, {String? name}) =>
      _index(columns, IndexType.unique, name);

  /// Adds a named primary key, including composite keys.
  IndexDefinition primary(List<String> columns, {String? name}) =>
      _index(columns, IndexType.primary, name);

  /// Adds a full-text index on MySQL, MariaDB, or PostgreSQL.
  IndexDefinition fullText(List<String> columns, {String? name}) =>
      _index(columns, IndexType.fullText, name);

  /// Adds a foreign key that must be completed with `references(...).on(...)`.
  ForeignKeyDefinition foreign(List<String> columns, {String? name}) {
    final definition = ForeignKeyDefinition(
      name ?? _name(columns, 'foreign'),
      columns,
    );
    _commands.add(definition);
    return definition;
  }

  /// Drops an existing column.
  void dropColumn(String name) =>
      _commands.add(SchemaChangeCommand(SchemaChange.dropColumn, name));

  /// Renames an existing column.
  void renameColumn(String from, String to) =>
      _commands.add(SchemaChangeCommand(SchemaChange.renameColumn, from, to));

  /// Drops an explicitly named index, including a unique index.
  void dropIndex(String name) =>
      _commands.add(SchemaChangeCommand(SchemaChange.dropIndex, name));

  /// Renames an explicitly named index, preserving its definition.
  void renameIndex(String from, String to) =>
      _commands.add(SchemaChangeCommand(SchemaChange.renameIndex, from, to));

  /// Drops a named unique index created with [unique].
  void dropUnique(String name) => dropIndex(name);

  /// Drops an explicitly named primary key constraint.
  ///
  /// MySQL and MariaDB always identify this key as PRIMARY.
  void dropPrimary(String name) =>
      _commands.add(SchemaChangeCommand(SchemaChange.dropPrimary, name));

  /// Drops a named full-text index on a supported database.
  void dropFullText(String name) =>
      _commands.add(SchemaChangeCommand(SchemaChange.dropFullText, name));

  /// Drops an explicitly named foreign key constraint.
  void dropForeign(String name) =>
      _commands.add(SchemaChangeCommand(SchemaChange.dropForeign, name));

  ColumnDefinition _column(
    String name,
    ColumnType type, {
    int? length,
    int? precision,
    int? scale,
    bool autoIncrement = false,
    bool fixed = false,
    List<String> allowed = const [],
  }) {
    final column = ColumnDefinition(
      name,
      type,
      length: length,
      precision: precision,
      scale: scale,
      autoIncrement: autoIncrement,
      fixed: fixed,
      allowed: allowed,
    );
    column.validate();
    _commands.add(column);
    return column;
  }

  ForeignIdColumnDefinition _foreignColumn(String name, ColumnType type) {
    final column = ForeignIdColumnDefinition(
      name,
      type,
      (constraintName) => foreign([name], name: constraintName),
    );
    _commands.add(column);
    return column;
  }

  void _morphs(String name, ColumnType type, bool nullable, String? indexName) {
    string('${name}_type').nullable(nullable);
    _column('${name}_id', type).nullable(nullable);
    index(['${name}_type', '${name}_id'], name: indexName);
  }

  IndexDefinition _index(List<String> columns, IndexType type, String? name) {
    final definition = IndexDefinition(
      name ??
          _name(
            columns,
            type == IndexType.normal ? 'index' : type.name.toLowerCase(),
          ),
      columns,
      type,
    );
    _commands.add(definition);
    return definition;
  }

  String _name(List<String> columns, String suffix) =>
      '${table.replaceAll('.', '_')}_${columns.join('_')}_$suffix';
}
