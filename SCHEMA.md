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

第三阶段迁移能力包括 `shouldRun`、命名连接、`--isolated` 和原生 schema
基线（`schema:dump --prune`）。互斥支持全部五种数据库；原生 dump/load 支持
MySQL、MariaDB、PostgreSQL 和文件型 SQLite，SQL Server 明确报不支持。
跨连接变更与默认连接历史不保证原子提交；详细使用方式、原生客户端要求及
剪除迁移后的回滚限制见 [MIGRATIONS.md](packages/laconic/MIGRATIONS.md)。

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

| 类别 | API |
|---|---|
| 整数、自增 | `id`、`increments`、`tiny/small/medium/bigIncrements`、`integer`、`tiny/small/medium/bigInteger`、对应 `unsigned*Integer` |
| 字符串 | `char(length:)`、`string(length:)`、`tinyText`、`text`、`mediumText`、`longText` |
| 数值 | `boolean`、`decimal(precision:, scale:)`、`float(precision:)`、`doublePrecision` |
| 日期与时间 | `date`、`year`、`time`、`timeTz`、`dateTime`、`dateTimeTz`、`timestamp`、`timestampTz` |
| 结构化值 | `json`、`jsonb`、`uuid`、`ulid`、`enumColumn(name, values)`、`set(name, values)` |
| 二进制与网络 | `binary(length:, fixed:)`、`ipAddress`、`macAddress` |
| 空间 | `geometry`、`geography`（原生类型；PostgreSQL 需要 PostGIS） |

列修饰方法：`nullable()`、`defaultTo(value)`、`primary()`、`unique()`、`unsigned()`、`change()`，
以及下面的注释、排序规则、列位置、时间默认值和生成列方法。

### 常用列修饰

| 修饰方法 | 支持与语义 |
|---|---|
| `comment(text)` | MySQL/MariaDB、PostgreSQL、SQL Server；SQLite 明确报错。`getColumns()` 的 `comment` 返回原生注释 |
| `charset(name)` | MySQL/MariaDB 原生列字符集；其他数据库明确报错 |
| `collation(name)` | 五种数据库的原生列排序规则；名称需在目标数据库中存在 |
| `first()` / `after(column)` | MySQL/MariaDB 新增列或 `change()` 时调整位置；建表请直接按顺序声明列，其他数据库明确报错 |
| `useCurrent()` | dateTime/timestamp 及受支持的带时区类型使用数据库当前时间作为默认值 |
| `useCurrentOnUpdate()` | MySQL/MariaDB 的 dateTime/timestamp 原生自动更新时间；其他数据库明确报错 |

```dart
await db.schema.table('posts', (table) {
  table.timestamp('published_at', precision: 3).nullable().useCurrent();
  // MySQL / MariaDB:
  table.timestamp('updated_at', precision: 3)
      .useCurrent().useCurrentOnUpdate().after('published_at');
  table.string('slug').charset('utf8mb4').collation('utf8mb4_bin')
      .comment("Article's slug");
});
```

`useCurrent()` 和 `defaultTo()` 以后调用的为准。`change()` 时需重新声明默认值、
自动更新时间及注释；省略注释会清除原注释。需要保留的字符集和排序规则也应重新声明。
MySQL/MariaDB 的 COMMENT 要求字符串字面量：为避免 SQL mode 造成内容变化，注释含反斜线或 NUL
时会在编译阶段报错。SQL Server 使用原生扩展属性 `MS_Description` 保存注释。

### 生成列

```dart
await db.schema.create('line_items', (table) {
  // SQLite / MySQL / MariaDB / PostgreSQL:
  table.id();
  table.integer('quantity');
  table.integer('price');
  table.integer('total').storedAs('quantity * price').nullable();
});
// SQL Server 使用原生计算列，类型由表达式推导：
await db.schema.table('line_items', (table) {
  table.computed('subtotal', 'quantity * price').persisted();
});
```

| 数据库 | 生成列接口 |
|---|---|
| SQLite | 类型方法后接 `virtualAs(sql)` / `storedAs(sql)`；给已有表添加 stored 列时原子重建 |
| MySQL | 类型方法后接 `virtualAs(sql)` / `storedAs(sql)` |
| MariaDB | 同 MySQL，但原生生成列不支持 NOT NULL，必须显式加 `nullable()` |
| PostgreSQL | 项目支持的 PostgreSQL 15 基线使用 `storedAs(sql)`；`virtualAs` 明确报错 |
| SQL Server | `computed(name, sql)`，可接 `persisted()`；类型和可空性默认由数据库推导，persisted 列可用 `nullable(false)` 强制 NOT NULL |

表达式是调用者提供的可信原始 SQL，不会绑定或改写。各数据库对函数确定性、类型和依赖的限制仍适用。
生成列不能设置普通默认值、自增、主键或自动更新时间；可以创建普通/唯一索引。
`change()` 不转换普通列与生成列，也不修改既有生成列；请显式删除再添加，依赖索引/约束由调用方处理。
其余列变化时会保留生成列，SQLite 复制数据时跳过生成列，由数据库重新计算。

`id()` 使用 SQLite INTEGER 或服务端数据库的有符号 BIGINT 自增主键。
`bigIncrements()` 与 `id()` 一致，其他 increments 方法使用对应的整数规格；
它们也不隐式使用 unsigned。`foreignId()` 使用相同的有符号 BIGINT，避免外键类型不匹配。
MySQL/MariaDB 可以显式使用 `id().unsigned()` 和 `foreignId('user_id').unsigned()`；
`unsigned*Integer` 是相应整数类型加 `.unsigned()` 的快捷方式，其他数据库明确拒绝 unsigned。
`timestamps()` 添加 nullable 的 `created_at` 和 `updated_at`，不会自动填充值。
DDL 默认值不能简单使用查询参数绑定，因此普通值会被方言编码为 SQL 字面量；
`defaultTo(Expression('CURRENT_TIMESTAMP'))` 允许显式提供可信 SQL 表达式。

### 外键与常用列快捷方法

```dart
await db.schema.create('posts', (table) {
  table.id();
  table.foreignId('user_id').nullable()
      .constrained('users', column: 'id', name: 'posts_user_fk')
      .nullOnDelete();
  table.nullableUuidMorphs('subject', indexName: 'posts_subject_index');
  table.timestamps(precision: 3);
  table.softDeletes();
  table.rememberToken();
});
```

`foreignId`、`foreignUuid`、`foreignUlid` 返回支持链式列修饰的
`ForeignIdColumnDefinition`。先调用 `nullable()` 等列修饰，再调用
`constrained('table', column: 'id', name: ...)`，返回普通 `ForeignKeyDefinition`。
也可使用 `references('column', name: ...).on('table')`。目标表名必须显式给出，
不推断模型、英文复数或 schema。外键动作支持 `cascadeOnDelete/Update`、
`nullOnDelete/Update`、`restrictOnDelete/Update`、`noActionOnDelete/Update`。

`morphs` / `uuidMorphs` / `ulidMorphs` 及其 `nullable*` 变体添加
`<name>_type` 字符串、`<name>_id` 对应类型，以及按 type、id 顺序的组合索引。
数字 morph ID 与 `id()` 一样使用 signed BIGINT；多态关联不添加数据库外键。
`indexName:` 可覆盖默认索引名称。

`softDeletes(name: 'deleted_at', precision:)` 添加 nullable timestamp；
`softDeletesTz` 使用对应时区类型。`rememberToken()` 添加 nullable VARCHAR(100)
（或方言等价类型）。`timestampsTz` 和 `nullableTimestamps` 分别提供时区和普通
时间戳对。它们只创建列，不自动填充时间、过滤软删除行或实现认证逻辑。
UUID/ULID 方法只定义存储类型，不生成 ID。

删除时可使用 `dropTimestamps` / `dropTimestampsTz`、`dropSoftDeletes` /
`dropSoftDeletesTz`、`dropRememberToken`、`dropMorphs(name, indexName:)`，以及
`dropConstrainedForeignId(name, constraintName:)`。后两者先删除索引/外键再删除列；
创建时指定了自定义名称，删除时也必须传入同一名称。

### 高级类型的方言行为

| 类型 | SQLite | MySQL / MariaDB | PostgreSQL | SQL Server |
|---|---|---|---|---|
| tiny / small / medium integer | INTEGER | TINYINT / SMALLINT / MEDIUMINT | SMALLINT / SMALLINT / INTEGER | TINYINT / SMALLINT / INT |
| tiny / medium / long text | TEXT | 对应原生类型 | TEXT | NVARCHAR(MAX) |
| `char` / `ulid` | CHAR(n) / CHAR(26)，长度不强制 | CHAR(n) / CHAR(26) | CHAR(n) / CHAR(26) | NCHAR(n) / CHAR(26) |
| `float(precision:)` | REAL | FLOAT(p) | p≤24 为 REAL，否则 DOUBLE PRECISION | FLOAT(p) |
| `jsonb` | TEXT | JSON | JSONB | NVARCHAR(MAX) |
| `enumColumn` | TEXT + CHECK | ENUM | TEXT + CHECK | NVARCHAR(MAX) + CHECK |
| `set` | 拒绝 | SET | 拒绝 | 拒绝 |
| `dateTimeTz` / `timestampTz` | TEXT | 拒绝 | TIMESTAMP WITH TIME ZONE | DATETIMEOFFSET |
| `timeTz` | TEXT | 拒绝 | TIME WITH TIME ZONE | 拒绝 |
| `year` | INTEGER | YEAR | SMALLINT | SMALLINT |
| `binary(length:, fixed:)` | 有 length/fixed 时拒绝 | BINARY(n) / VARBINARY(n) | 有 length/fixed 时拒绝 | BINARY(n) / VARBINARY(n) |
| `ipAddress` / `macAddress` | VARCHAR(45/17) | VARCHAR(45/17) | INET / MACADDR | NVARCHAR(45/17) |
| `geometry` | 拒绝 | GEOMETRY | PostGIS GEOMETRY | GEOMETRY |
| `geography` | 拒绝 | 拒绝 | PostGIS GEOGRAPHY | GEOGRAPHY |

这些映射采用数据库原生范围和比较语义；例如 SQL Server TINYINT 为 0–255，
SQLite 不强制整数位宽或字符长度。IP/MAC 的字符串映射不进行格式校验。
空间类型当前只定义通用原生列，不提供 subtype、SRID 修饰或自动安装 PostGIS。
几何值的构造、编码和读取仍使用驱动支持的原生 SQL/类型处理。

时间类型接受可选 `precision:`。MySQL/MariaDB/PostgreSQL 支持 0–6，SQL Server
支持 0–7；SQLite 保存文本，不强制小数精度或时区转换。省略 precision 保持原有
数据库默认值。MySQL/MariaDB 没有带时区列类型，使用显式 UTC 的 `dateTime` /
`timestamp`，不把 `*Tz` 静默降级。普通 `timestamp()` 在 SQL Server 仍是 DATETIME2。

`float` 接受 1–53 位二进制精度；各数据库按自身支持的单/双精度档位存储。
`binary()` 不指定长度时仍分别使用 BLOB/BYTEA/VARBINARY(MAX)。指定 fixed 必须同时
给 length；MySQL/MariaDB 的 BINARY 最大 255、VARBINARY 最大 65535（还受行大小限制），
SQL Server 指定长度最大 8000。不支持长度语义的数据库会在执行 DDL 前报错。

Dart 的 `enum` 是保留字，因此枚举入口命名为 `enumColumn`。允许值列表会做不可变
快照，必须非空、无重复、不含 NUL；SET 最多 64 个成员，成员不能含逗号。
MySQL/MariaDB 为避免 SQL mode 改变枚举字面量含义，拒绝带反斜杠的 ENUM/SET 成员。
值的大小写、尾随空格和无效输入行为仍取决于数据库排序规则及 SQL mode。
CHECK 枚举的 nullable 列允许 NULL；调整 CHECK 枚举的成员列表不支持直接 `.change()`，
需要显式处理约束。MySQL/MariaDB 原生 ENUM 可 `.change()`；更换其他类型时既有 CHECK
约束仍可能保留。现有 PostgreSQL `json()` 继续使用 JSONB，新增 `jsonb()` 不改变旧映射。

API 名称参照 [Laravel Blueprint](https://laravel.com/framework/docs/13.x/migrations#available-column-types)，
上述 signed ID、显式目标表和不支持类型报错是 Laconic 的明确约定。

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

`primary`、`unique`、`index`、`fullText`、`foreign` 都接受列名列表，因此支持组合键。
`index`、`unique`、`primary`、`fullText` 返回 `IndexDefinition`。
需要后续删除的唯一索引应使用表级 `unique([...], name: ...)`，然后 `dropUnique(name)` 或 `dropIndex(name)`。
`dropPrimary(name)` 删除显式命名的表级主键约束；MySQL/MariaDB 总是使用原生 PRIMARY 名称。
不会为自增列自动移除自增属性，也不会猜测和移除依赖外键。
`dropForeign(name)` 删除显式命名的外键。默认名称为表名、列名和类型拼接，
长表名或列名可能超过数据库标识符长度限制，此时应显式指定较短名称。

### 全文索引与索引重命名

```dart
await db.schema.table('posts', (table) {
  table.fullText(['title', 'body'], name: 'posts_search');
  // PostgreSQL 可接 .language('english')，查询时使用相同的 language。
});
await db.schema.table('posts', (table) {
  table.renameIndex('posts_search', 'posts_search_new');
});
await db.schema.table('posts', (table) => table.dropFullText('posts_search_new'));
```

MySQL/MariaDB 使用 FULLTEXT 索引，不接受 `language()`；PostgreSQL 使用 GIN 表达式索引，
默认 `english`，对各列先 COALESCE 再拼接 tsvector，与现有 `whereFullText()` 保持一致。
SQLite 的全文检索需要专门的 FTS 虚拟表，SQL Server 还需要目录和唯一键等配置，
两者的 `fullText()` / `dropFullText()` 均明确报错；不会退化为普通索引。

`renameIndex(from, to)` 保留索引定义。SQLite 只重建显式索引，保留唯一性、表达式、
排序规则、方向和 WHERE 条件，整个过程使用事务/保存点；可在开启外键的外层事务中运行。
SQLite 的自动约束索引不可重命名；仅索引重命名与 `renameColumn()` 请分开调用 `table()`，
需要表重建的混合操作则沿用重建规则，将 `renameColumn()` 放在最后。

## 修改已有列

```dart
await db.schema.table('users', (table) {
  table.string('name', length: 300).nullable().defaultTo('guest').change();
});
```

`change()` 重新声明列类型、可空性和默认值：没有 `nullable()` 就是 NOT NULL，
没有 `defaultTo()` 就移除原默认值；MySQL/MariaDB 的 unsigned 也需要重新声明。
既有主键、唯一键及普通索引保留；
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
| `SchemaColumn` | `name`、`typeName`、`type`、`nullable`、`defaultValue`、`autoIncrement`、`collation`、`comment`、`generated`、`generation`、`primaryPosition`、`defaultConstraint` |
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
| 全文索引 | 明确报错，使用 FTS 虚拟表 | FULLTEXT | GIN + language | 明确报错 |
| 索引重命名 / 删除 | 显式索引原子重建 / 删除 | 支持 | 支持 | 支持 |
| 删除命名主键 | 重建 | 支持 | 支持 | 支持 |
| 生成列 | virtual / stored | virtual / stored；MariaDB 需 nullable | stored | computed / persisted |
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

当前不提供自动 schema diff 或 Laravel 全部 Blueprint 方法。可以通过现有 `db.statement()` 使用
数据库专有操作。不要把迁移回滚理解为数据备份。

## 第三方数据库接入

1. 按现有方式实现 `DatabaseDriver`，返回自己的 `SqlGrammar` 子类。
2. 在该 Grammar 实现 `compileColumnType`、`compileAutoIncrement`、
   `compileTableExists`、`compileColumnListing`，并覆盖需要定制的标识符、
   默认值、建表/改表编译方法。
   `ColumnType` 新增高级类型，穷尽 switch 必须同步；不支持的类型应显式抛出异常。
   `compileUnsigned` 默认拒绝 unsigned，`supportsNativeEnum` 默认 false，
   此时 `compileColumnDefinition` 会给枚举添加 CHECK 并拒绝直接变更枚举成员。
   `compileTemporalPrecision` 验证方言时间精度；列的 `allowed`、`fixed`、`isUnsigned`
   参数应参与编译；DDL 继续使用现有 grammar。
   元数据实现 `compileTables/Views/Columns/Indexes/ForeignKeys`，按 SchemaBuilder 使用的
   字段别名返回行；需要时用 `normalizeColumnMetadata` 补齐原生信息。
   列修改实现 `compileChangeColumn`；`compileAlterTable` 新增可选的 `columns`、`objects`
   快照参数，已有覆盖方法必须同步签名。需要重建的方言实现 `requiresTableRebuild` 和
   `compileSchemaObjects`，驱动实现 `SchemaTransactionDriver`；编译器仍保持无状态、无 I/O。
   新增 `ColumnType.computed`、`IndexType.fullText` 和索引变更的 `SchemaChange` 枚举值，
   第三方穷尽 switch 必须同步；按需覆盖 `compileColumnCharset/Collation/Comment/Extras/Position/Default/OnUpdate/Generation/Nullability`
   和 `compileCurrentTimestamp`。新增修饰的默认实现会拒绝不支持的功能。
   仅需要索引快照时覆盖 `requiresSchemaSnapshot`；需要原子索引替换时覆盖 `requiresSchemaTransaction`。
   `SchemaTransactionDriver.schemaTransaction` 新增 `disableForeignKeys` 命名参数（默认 true）：
   索引操作传 false，必须保留外键检查并支持外层事务内的保存点。预览驱动仍只记录 SQL。
3. 明确设置 `supportsSchemaTransactions`；默认值为 false。这个声明只适用于
   普通迁移 DDL，具体 migration 可以关闭自动事务。
4. 按需实现可选的 `MigrationLockDriver` / `SchemaStateDriver`：前者提供跨进程、跨迁移事务的
   非阻塞数据库锁，竞争抛出 `MigrationLockException`；后者通过原生客户端 dump/load。
   原有 `DatabaseDriver` 无新增必需成员，不支持时核心入口会明确报错。
5. 复用 `packages/laconic/test/regressions/schema_regressions.dart` 的行为测试，并添加数据库特有用例。

公共类型从 `package:laconic/laconic.dart` 导出。第三方不需要导入 `src`，
也不需要修改核心包或 Migration 包里的注册表。
现有 `extends SqlGrammar` 子类会继承新增方法；未实现的列类型和结构检查会抛出
清晰的 `LaconicException`。使用 `implements SqlGrammar` 的实现者必须补齐新增成员。
