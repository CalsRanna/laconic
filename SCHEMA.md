# Schema Builder 与 Migration

本页描述尚未发布的 workspace API。使用本仓库版本的核心包和配套驱动；发布前需要一起更新最低依赖版本。

## 架构

`laconic` 核心同时提供 `QueryBuilder`、`SchemaBuilder`、`Blueprint` 和统一的
`SqlGrammar`。`DatabaseDriver` 的原有接口保持不变，继续通过 `grammar` 提供方言；需要重建表的驱动
额外实现可选 `SchemaTransactionDriver`，负责独占连接、事务与连接设置恢复。
各驱动的同一个 Grammar 编译查询、写入和 DDL。驱动内部用私有 mixin/part 分文件组织
DDL 实现，没有新增公开的 SchemaGrammar 或 SchemaProvider。

核心包还内置 `Migration`、`Migrator` 和 CLI，负责迁移顺序、历史、批次和回滚。
迁移类型和 CLI API 统一从 `package:laconic/laconic.dart` 导出，
命令入口为 `dart run laconic`。核心因 CLI 引入 args/cli_util/io/path，
不依赖任何具体数据库驱动；应用通过 `DatabaseConfiguration.createDatabase()` 提供所选驱动的连接。
真实数据库的迁移测试归各驱动包所有。文件生成与命令用法见
[Migration CLI](packages/laconic/MIGRATIONS.md#cli)。

迁移 CLI 支持 `migrate/rollback/status/reset/refresh/fresh`、按批次回滚、SQL
预览和生产环境 `--force`。`fresh` 通过 `db.schema.dropAllTables(schema: ...)`
清理历史表所在 schema 内的全部表（包括未登记迁移的表），随后重跑迁移。
视图及外部依赖不会自动删除；具体范围、事务与预览限制见迁移指南。

## 创建与修改表

```dart
final db = Laconic(SqliteDriver(SqliteConfig('app.db')));

await db.schema.create('users', (table) {
  table.id();
  table.string('email', length: 255);
  table.string('name').nullable();
  table.boolean('active').defaultTo(true);
  table.timestamps();
  table.unique(['email'], name: 'users_email_unique');
});

await db.schema.table('users', (table) {
  table.integer('age').nullable();
  table.index(['age'], name: 'users_age_index');
  table.renameColumn('name', 'display_name');
});

await db.schema.table('users', (table) {
  table.dropIndex('users_age_index');
  table.dropColumn('age');
});

print(await db.schema.hasTable('users'));
print(await db.schema.hasColumn('users', 'email'));
print(await db.schema.getColumnListing('users'));

await db.schema.rename('users', 'members');
await db.schema.dropIfExists('members');
await db.close();
```

Schema 操作通过 `Laconic.statement/select` 执行，会触发已有查询钩子。
每次 create/table 操作会先编译全部 SQL，再按顺序执行；编译失败不会执行其中任何一条。
普通原生 DDL 执行阶段的失败仍可能留下已执行的语句，不自动开启事务。
SQLite 重建操作会在独占连接的事务中读取快照、完整编译并执行；失败回滚整次操作。

表名支持 `table` 和 `schema.table` 两种形式；列名、索引名按单个标识符处理。
所有标识符都由具体方言转义。`rename` 的目标名称必须不带 schema，保持原命名空间。
`hasColumn` 按数据库返回的列名精确匹配。

## 列、索引与外键

列方法：`id`、`integer`、`bigInteger`、`string`、`text`、`boolean`、`decimal`、
`doublePrecision`、`date`、`dateTime`、`timestamp`、`binary`、`json`、`uuid`、`timestamps`。
列修饰方法：`nullable()`、`defaultTo(value)`、`primary()`、`unique()`、`change()`。

`id()` 使用 SQLite INTEGER 或服务端数据库的有符号 BIGINT 自增主键。
外键列应使用匹配类型，例如 `bigInteger('user_id')`；这里不隐式使用 unsigned。
`timestamps()` 添加 nullable 的 `created_at` 和 `updated_at`，不会自动填充值。
DDL 默认值不能简单使用查询参数绑定，因此普通值会被方言编码为 SQL 字面量；
`defaultTo(Expression('CURRENT_TIMESTAMP'))` 允许显式提供可信 SQL 表达式。

```dart
await db.schema.create('posts', (table) {
  table.id();
  table.bigInteger('user_id');
  table.string('title');
  table.foreign(['user_id'], name: 'posts_user_foreign')
      .references(['id']).on('users').onDelete('cascade');
  table.index(['user_id']);
});
```

`primary`、`unique`、`index`、`foreign` 都接受列名列表，因此支持组合键。
需要后续删除的唯一索引应使用表级 `unique([...], name: ...)`，然后 `dropIndex(name)`。
`dropForeign(name)` 删除显式命名的外键。默认名称为表名、列名和类型拼接，
长表名或列名可能超过数据库标识符长度限制，此时应显式指定较短名称。

## 修改已有列

```dart
await db.schema.table('users', (table) {
  table.string('name', length: 300).nullable().defaultTo('guest').change();
});
```

`change()` 重新声明列类型、可空性和默认值：没有 `nullable()` 就是 NOT NULL，
没有 `defaultTo()` 就移除原默认值。既有主键、唯一键及普通索引保留；
`change()` 不接受 `primary()`、`unique()` 或 `id()`，请用单独的键操作。
自增/identity 属性不会因普通列类型修改而被移除。不存在的列、建表时使用 `change()`
等用法会在执行 DDL 前报错。对同一回调中新添加的列，请直接定义其最终类型。
这与 [Laravel 的列修改语义](https://laravel.com/framework/docs/13.x/migrations#modifying-columns)
对齐；当前未提供 Laravel 的全部列修饰方法。

MySQL/MariaDB 使用 MODIFY COLUMN；PostgreSQL 使用 ALTER COLUMN；SQL Server
会查出并移除原默认约束、修改列，再添加新默认值。SQL Server 的索引、计算列等依赖
可能阻止类型或可空性变更，需要调用方显式处理依赖；没有自动删除并重建这些依赖。
原生类型转换限制仍由数据库报告。服务器数据库的多语句改表仍遵循原有事务约定。

## 结构元数据

```dart
final tables = await db.schema.getTables();
final views = await db.schema.getViews(schema: 'main'); // SQLite；其他数据库填写实际 schema
final columns = await db.schema.getColumns('users');
final indexes = await db.schema.getIndexes('users');
final foreignKeys = await db.schema.getForeignKeys('posts');

print(columns.first.type);
print(await db.schema.getColumnType('users', 'name', fullDefinition: true));
print(await db.schema.hasColumns('users', ['id', 'name']));
print(await db.schema.hasIndex('users', ['email'], type: 'unique'));
```

这些方法与 [Laravel 的结构检查入口](https://laravel.com/framework/docs/13.x/database#inspecting-your-databases)
对应，返回以下不可变元数据对象；列表顺序沿用数据库定义：

| 返回类型 | 主要字段 |
|---|---|
| `SchemaTable`（表或视图） | `name`、`schema`、`qualifiedName`、可用时的 `definition` |
| `SchemaColumn` | `name`、`typeName`、`type`、`nullable`、`defaultValue`、`autoIncrement`、`collation`、`generated`、`generation`、`primaryPosition`、`defaultConstraint` |
| `SchemaIndex` | `name`、按键顺序排列的 `columns`、`unique`、`primary`、`type`、可用时的 `definition` |
| `SchemaForeignKey` | `name`、`columns`、`foreignSchema`、`foreignTable`、`foreignColumns`、`onUpdate`、`onDelete` |

`getTables`/`getViews` 默认查询当前 schema（SQLite 为 main）；可用 `schema:` 指定。
表级检查支持 `schema.table`。`getColumnType` 默认返回原生基础类型名，
`fullDefinition: true` 包含长度/精度等数据库返回的类型信息。
`defaultValue` 是数据库返回的默认值文本，不转换为 Dart 字面量；各方言的引号和表达式
表示可能不同。复合索引和外键保留列顺序；索引的 INCLUDE 列不属于键列。
表达式索引的 `columns` 对应项为 null，可通过可用的定义 SQL 查看表达式。
索引 `definition` 在 SQLite/PostgreSQL 为建索引 SQL，在 SQL Server 为过滤谓词，MySQL/MariaDB 未提供时为 null。
SQLite 不公开外键约束名，因此 `SchemaForeignKey.name` 为 null；隐式引用主键的
`foreignColumns` 对应项也可能为 null。数据库未提供的可选信息为 null。
`hasIndex` 支持索引名或有序列名列表，`type:` 可选 primary、unique 或原生索引类型。

## SQLite 自动重建

SQLite 对 `change()`、删除列、增删外键、添加主键，以及原生 ADD COLUMN 不支持的
键或表达式默认值采用重建。流程遵循 [SQLite 官方改表步骤](https://www.sqlite.org/lang_altertable.html#otheralter)：
先建新表、复制数据、删除原表、再恢复原表名，随后恢复索引和触发器；不会先重命名原表。

重建保留未修改列的定义、CHECK、COLLATE、生成列、既有键、部分/表达式索引、触发器、
视图引用、可访问的 rowid 和 AUTOINCREMENT 序列高水位，并支持附加数据库及 WITHOUT ROWID 表。
删除列会移除使用该列的索引和本表键；如果其仍被保留的 CHECK、生成列、触发器或视图引用，
会在执行 DDL 前报错。外部表引用导致的无效外键关系也会回滚。
重建回调中的 `renameColumn` 必须放在其他操作之后；SQLite 原生列重命名会同步索引和视图。
虚拟表不支持重建；STRICT 表仍受 SQLite 原生类型限制。

驱动在事务前保存并关闭外键检查，事务内独占连接，完成后检查外键完整性并恢复原设置。
原本关闭外键的连接会保持关闭，不额外校验原有外键数据。任何复制、DDL、完整性检查或
查询钩子异常都会回滚；已有外层事务且外键已关闭时使用 SAVEPOINT。
**外键开启的外层事务不能重建**，会在任何 DDL 前报错。这样的 SQLite 迁移应声明：

```dart
@override
bool get withinTransaction => false;
```

此时每次 `schema.table()` 重建仍然原子执行，但整个迁移及历史记录不再共享一个事务。
不要在普通数据事务中关闭外键来绕过此限制。

## 当前方言能力

| 能力 | SQLite | MySQL / MariaDB | PostgreSQL | SQL Server |
|---|---|---|---|---|
| 创建、删除、重命名表 | 支持 | 支持 | 支持 | 支持 |
| 添加、删除、重命名列 | 支持，必要时重建 | 支持 | 支持 | 支持，受依赖约束限制 |
| 普通 / 唯一索引 | 支持 | 支持 | 支持 | 支持 |
| 建表时主键 / 外键 | 支持 | 支持 | 支持 | 支持 |
| 改表时新增主键 / 外键、删除外键 | 重建支持 | 支持 | 支持 | 支持 |
| `change()` / 结构元数据 | 支持 | 支持 | 支持 | 支持，受原生依赖限制 |
| 普通迁移 DDL 事务 | 支持 | 不自动开启 | 支持 | 支持 |
| JSON 表示 | TEXT | JSON | JSONB | NVARCHAR(MAX) |
| UUID 表示 | VARCHAR(36) | CHAR(36) | UUID | UNIQUEIDENTIFIER |

SQLite 需要调用方开启 `PRAGMA foreign_keys = ON` 才会执行外键检查。
SQLite 原生添加列不支持的主键、内联 unique 或表达式默认值由重建处理。
SQL Server 删除列前需要先移除依赖约束；本实现不会猜测并删除已有的默认约束。
MySQL/MariaDB 的 InnoDB 外键不支持 `SET DEFAULT`；SQL Server 不支持 `RESTRICT`。
上述已知差异会在编译阶段明确报错；其他原生数据库限制仍由数据库报告。

SQLite 的类型亲和性不会强制 varchar 长度或 decimal 精度。JSON/UUID 的原生校验、
时间类型语义也随数据库不同；SQL Server 的 `timestamp()` 映射为 DATETIME2。

当前不提供自动 schema diff、schema dump 或 Laravel 全部 Blueprint 方法。可以通过现有 `db.statement()` 使用
数据库专有操作。不要把迁移回滚理解为数据备份。

## 第三方数据库接入

1. 按现有方式实现 `DatabaseDriver`，返回自己的 `SqlGrammar` 子类。
2. 在该 Grammar 实现 `compileColumnType`、`compileAutoIncrement`、
   `compileTableExists`、`compileColumnListing`，并覆盖需要定制的标识符、
   默认值、建表/改表编译方法。
   元数据实现 `compileTables/Views/Columns/Indexes/ForeignKeys`，按 SchemaBuilder 使用的
   字段别名返回行；需要时用 `normalizeColumnMetadata` 补齐原生信息。
   列修改实现 `compileChangeColumn`；`compileAlterTable` 新增可选的 `columns`、`objects`
   快照参数，已有覆盖方法必须同步签名。需要重建的方言实现 `requiresTableRebuild` 和
   `compileSchemaObjects`，驱动实现 `SchemaTransactionDriver`；编译器仍保持无状态、无 I/O。
3. 明确设置 `supportsSchemaTransactions`；默认值为 false。这个声明只适用于
   普通迁移 DDL，具体 migration 可以关闭自动事务。
4. 复用 `packages/laconic/test/regressions/schema_regressions.dart` 的行为测试，并添加数据库特有用例。

公共类型从 `package:laconic/laconic.dart` 导出。第三方不需要导入 `src`，
也不需要修改核心包或 Migration 包里的注册表。
现有 `extends SqlGrammar` 子类会继承新增方法；未实现的列类型和结构检查会抛出
清晰的 `LaconicException`。使用 `implements SqlGrammar` 的实现者必须补齐新增成员。
