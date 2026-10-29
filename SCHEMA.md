# Schema Builder 与 Migration

本页描述尚未发布的 workspace API。使用本仓库版本的核心包和配套驱动；发布前需要一起更新最低依赖版本。

## 架构

`laconic` 核心同时提供 `QueryBuilder`、`SchemaBuilder`、`Blueprint` 和统一的
`SqlGrammar`。`DatabaseDriver` 的接口保持不变，继续通过 `grammar` 提供方言。
各驱动的同一个 Grammar 编译查询、写入和 DDL。驱动内部用私有 mixin/part 分文件组织
DDL 实现，没有新增公开的 SchemaGrammar 或 SchemaProvider。

核心包还内置 `Migration`、`Migrator` 和 CLI，负责迁移顺序、历史、批次和回滚。
迁移类型和 CLI API 统一从 `package:laconic/laconic.dart` 导出，
命令入口为 `dart run laconic`。核心因 CLI 引入 args/cli_util/io/path，
不依赖任何具体数据库驱动；应用通过 `DatabaseConfiguration.createDatabase()` 提供所选驱动的连接。
真实数据库的迁移测试归各驱动包所有。文件生成与命令用法见
[Migration CLI](packages/laconic/MIGRATIONS.md#cli)。

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
执行阶段的失败仍可能留下已执行的语句，SchemaBuilder 不自动开启事务。

表名支持 `table` 和 `schema.table` 两种形式；列名、索引名按单个标识符处理。
所有标识符都由具体方言转义。`rename` 的目标名称必须不带 schema，保持原命名空间。
`hasColumn` 按数据库返回的列名精确匹配。

## 列、索引与外键

列方法：`id`、`integer`、`bigInteger`、`string`、`text`、`boolean`、`decimal`、
`doublePrecision`、`date`、`dateTime`、`timestamp`、`binary`、`json`、`uuid`、`timestamps`。
列修饰方法：`nullable()`、`defaultTo(value)`、`primary()`、`unique()`。

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

## 当前方言能力

| 能力 | SQLite | MySQL / MariaDB | PostgreSQL | SQL Server |
|---|---|---|---|---|
| 创建、删除、重命名表 | 支持 | 支持 | 支持 | 支持 |
| 添加、删除、重命名列 | 支持，受原生限制 | 支持 | 支持 | 支持，受依赖约束限制 |
| 普通 / 唯一索引 | 支持 | 支持 | 支持 | 支持 |
| 建表时主键 / 外键 | 支持 | 支持 | 支持 | 支持 |
| 改表时新增主键 / 外键、删除外键 | 明确报错 | 支持 | 支持 | 支持 |
| 普通迁移 DDL 事务 | 支持 | 不自动开启 | 支持 | 支持 |
| JSON 表示 | TEXT | JSON | JSONB | NVARCHAR(MAX) |
| UUID 表示 | VARCHAR(36) | CHAR(36) | UUID | UNIQUEIDENTIFIER |

SQLite 需要调用方开启 `PRAGMA foreign_keys = ON` 才会执行外键检查。
SQLite 添加列不支持主键、内联 unique 或表达式默认值；本实现不会自动重建表。
SQL Server 删除列前需要先移除依赖约束；本实现不会猜测并删除已有的默认约束。
MySQL/MariaDB 的 InnoDB 外键不支持 `SET DEFAULT`；SQL Server 不支持 `RESTRICT`。
上述已知差异会在编译阶段明确报错；其他原生数据库限制仍由数据库报告。

SQLite 的类型亲和性不会强制 varchar 长度或 decimal 精度。JSON/UUID 的原生校验、
时间类型语义也随数据库不同；SQL Server 的 `timestamp()` 映射为 DATETIME2。

首版不提供列类型修改、自动 schema diff、SQLite 自动重建表、完整结构元数据、
schema dump 或 Laravel 全部 Blueprint 方法。可以通过现有 `db.statement()` 使用
数据库专有操作。不要把迁移回滚理解为数据备份。

## 第三方数据库接入

1. 按现有方式实现 `DatabaseDriver`，返回自己的 `SqlGrammar` 子类。
2. 在该 Grammar 实现 `compileColumnType`、`compileAutoIncrement`、
   `compileTableExists`、`compileColumnListing`，并覆盖需要定制的标识符、
   默认值、建表/改表编译方法。
3. 明确设置 `supportsSchemaTransactions`；默认值为 false。这个声明只适用于
   普通迁移 DDL，具体 migration 可以关闭自动事务。
4. 复用 `packages/laconic/test/regressions/schema_regressions.dart` 的行为测试，并添加数据库特有用例。

公共类型从 `package:laconic/laconic.dart` 导出。第三方不需要导入 `src`，
也不需要修改核心包或 Migration 包里的注册表。
现有 `extends SqlGrammar` 子类会继承新增方法；未实现的列类型和结构检查会抛出
清晰的 `LaconicException`。使用 `implements SqlGrammar` 的实现者必须补齐新增成员。
