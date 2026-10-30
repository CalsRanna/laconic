# Laconic

<p align="right">
  <a href="README.md">English</a> | <a href="README_ZH.md">简体中文</a>
</p>

一个 Laravel 风格的 Dart SQL 查询构建器，支持 MySQL、MariaDB、SQLite、PostgreSQL 和 SQL Server 数据库。提供流畅的链式 API 来优雅地构建数据库查询。

## 特性

- **Laravel 风格 API** - 130+ 个链式方法，覆盖过滤、联表、聚合、子查询、分页和写入
- **多数据库支持** - 通过独立驱动包支持 MySQL、MariaDB、SQLite、PostgreSQL 和 SQL Server
- **子查询** - SELECT/FROM/JOIN 子查询、WHERE EXISTS、IN 子查询、insert-using 和 UNION
- **分页与流式** - `paginate`、`simplePaginate`、`cursorPaginate`、原生 `cursor()`、`lazy()`、`lazyById()`
- **JSON 与全文** - JSON contains/key/length/overlaps 与 `->` 路径；MySQL/PostgreSQL 全文；SQLite FTS5
- **方言特性** - MySQL binary/索引提示/straight join，PostgreSQL `updateFrom`/LATERAL，`groupLimit`
- **完整 JOIN 支持** - INNER、LEFT、RIGHT、CROSS、子查询 JOIN、LATERAL JOIN 和 30+ 条件方法
- **行锁** - `FOR UPDATE`、共享锁以及可移植的原始锁子句
- **Upsert 与批量写入** - `insertGetId`、`upsert`、`insertUsing`、`insertOrIgnoreUsing`、`updateOrInsert`、`incrementEach`
- **日期 WHERE** - `whereDate`、`whereTime`、`whereDay`、`whereMonth`、`whereYear`，支持比较符
- **分块处理** - `chunk`、`chunkById`、`each`、`cursor`、`lazy`、`lazyById`、`eachById`
- **调试工具** - `toSql()`、`getBindings()`、`toRawSql()`、`dump()`、`dd()` 和查询钩子
- **参数化查询** - 查询值使用参数绑定；原始 SQL 和标识符须来自可信来源
- **事务支持** - 完整的事务管理
- **查询监听器** - 内置调试和日志功能

## 包

| 包 | 描述 | 版本 |
|---|------|------|
| [laconic](https://pub.dev/packages/laconic) | 核心查询构建器 | 6.0.0 |
| [laconic_sqlite](https://pub.dev/packages/laconic_sqlite) | SQLite 驱动 | 4.0.0 |
| [laconic_mysql](https://pub.dev/packages/laconic_mysql) | MySQL 驱动 | 5.0.0 |
| [laconic_postgresql](https://pub.dev/packages/laconic_postgresql) | PostgreSQL 驱动 | 4.0.0 |
| [laconic_mariadb](packages/laconic_mariadb/README.md) | MariaDB 10.11+ | 1.0.0 (开发中) |
| [laconic_sqlserver](packages/laconic_sqlserver/README.md) | SQL Server 2022+ | 1.0.0 (开发中) |

MariaDB 和 SQL Server 驱动目前仅在本 workspace 中提供，尚未发布到 pub.dev。用法、连接配置及方言限制见上方包文档。

## 安装

核心包声明 Dart SDK `>=3.7.0 <4.0.0`。运行整个 workspace 或本页的 SQLite 示例时，
当前解析的 `sqlite3 3.3.4` 需要 Dart 3.10 或更高的 3.x SDK。

添加核心包和你需要的驱动：

```yaml
dependencies:
  laconic: ^6.0.0
  laconic_sqlite: ^4.0.0    # SQLite
  # laconic_mysql: ^5.0.0   # MySQL
  # laconic_postgresql: ^4.0.0  # PostgreSQL
```

然后运行：

```bash
dart pub get
```

## 快速开始

### SQLite

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

void main() async {
  final laconic = Laconic(SqliteDriver(SqliteConfig('app.db')));

  // 查询用户
  final users = await laconic.table('users').where('active', true).get();

  // 别忘了关闭连接
  await laconic.close();
}
```

### MySQL

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';

void main() async {
  final laconic = Laconic(MysqlDriver(MysqlConfig(
    host: '127.0.0.1',
    port: 3306,
    database: 'my_database',
    username: 'root',
    password: 'password',
  )));

  final users = await laconic.table('users').get();
  await laconic.close();
}
```

### PostgreSQL

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_postgresql/laconic_postgresql.dart';

void main() async {
  final laconic = Laconic(PostgresqlDriver(PostgresqlConfig(
    host: '127.0.0.1',
    port: 5432,
    database: 'my_database',
    username: 'postgres',
    password: 'password',
  )));

  final users = await laconic.table('users').get();
  await laconic.close();
}
```

### 查询监听器（调试用）

```dart
final laconic = Laconic(
  SqliteDriver(SqliteConfig('app.db')),
  listen: (query) {
    print('SQL: ${query.sql}');
    print('Bindings: ${query.bindings}');
  },
);
```

## 基本用法

### 查询构建器

```dart
// 获取所有记录
final users = await laconic.table('users').get();

// 按主键查找（简写）
final user = await laconic.table('users').find(1);

// 查找第一条匹配记录（简写）
final admin = await laconic.table('users').firstWhere('role', 'admin');

// 获取第一条记录（无结果时抛出异常）
final user = await laconic.table('users').first();

// 获取唯一记录（无结果或多条结果时抛出异常）
final user = await laconic.table('users').where('email', 'john@example.com').sole();

// 选择特定列
final names = await laconic.table('users').select(['name', 'age']).get();

// 统计记录数
final count = await laconic.table('users').count();

// 检查记录是否存在
final exists = await laconic.table('users').where('id', 1).exists();

// 提取列值
final names = await laconic.table('users').pluck('name');           // List
final map = await laconic.table('users').pluck('name', key: 'id');  // Map<id, name>

// 调试查询（打印 SQL + 参数，返回 this）
laconic.table('users').where('active', true).dump();

// 获取 SQL 不执行
final sql = laconic.table('users').where('age', 18, comparator: '>').toSql();
```

### WHERE 子句

空的 `whereIn` 编译为恒假条件，`whereNotIn` 编译为恒真条件，仍参与完整的布尔运算。
例如 `whereIn('id', []).orWhere('id', 1)` 仍可返回 id 为 1 的行。

```dart
// 基本 where
final adults = await laconic.table('users')
    .where('age', 18, comparator: '>=')
    .get();

// 多条件（AND）
final results = await laconic.table('users')
    .where('age', 18, comparator: '>')
    .where('status', 'active')
    .get();

// OR 条件
final users = await laconic.table('users')
    .where('role', 'admin')
    .orWhere('role', 'moderator')
    .get();

// WHERE IN / NOT IN
final users = await laconic.table('users')
    .whereIn('id', [1, 2, 3])
    .get();

// WHERE NULL / NOT NULL
final usersWithEmail = await laconic.table('users')
    .whereNotNull('email')
    .get();

// WHERE BETWEEN
final users = await laconic.table('users')
    .whereBetween('age', min: 18, max: 30)
    .get();

// LIKE / NOT LIKE（语法糖）
final matches = await laconic.table('users')
    .whereLike('name', 'John%')
    .get();

// 嵌套 WHERE 分组（括号子条件）
final users = await laconic.table('users')
    .where('status', 'active')
    .whereNested((q) => q.where('age', 30).orWhere('role', 'admin'))
    .get();
// SQL: WHERE status = ? AND (age = ? OR role = ?)

// 日期 WHERE
final todayUsers = await laconic.table('users').whereDate('created_at', DateTime.now()).get();
final janUsers = await laconic.table('users').whereMonth('created_at', 1).get();
final year2025 = await laconic.table('users').whereYear('created_at', 2025).get();

// WHERE EXISTS 子查询
final usersWithPosts = await laconic.table('users u')
    .whereExists((q) => q.from('posts p').whereColumn('p.user_id', 'u.id'))
    .get();

// 条件 WHERE（Laravel 的 when/unless）
final searchName = 'John';
final users = await laconic.table('users')
    .when(searchName.isNotEmpty, (q) => q.where('name', searchName))
    .get();
```

### JOIN 操作

```dart
// INNER JOIN
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// 带 WHERE + LIKE 条件的 LEFT JOIN
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .leftJoin(
      'posts p',
      (join) => join
          .on('u.id', 'p.user_id')
          .where('p.status', 'published')
          .whereLike('p.title', '%Dart%'),
    )
    .get();

// RIGHT JOIN
final results = await laconic.table('users u')
    .rightJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// CROSS JOIN
final results = await laconic.table('users').crossJoin('roles').get();
```

`sum()` 返回 `num`，空结果或全 NULL 时返回 `0`；`avg()` 返回 `double?`；
`min()` / `max()` 返回 `Object?`，保留驱动返回的数字、字符串或日期类型。
后三者在没有非 NULL 值时返回 `null`。`first()` / `find()` 的无结果抛异常约定不变。

`insertUsing()`、`insertOrIgnoreUsing()`、`insertOrIgnore()` 和 `upsert()`
返回数据库报告的受影响行数（`Future<int>`）；MySQL/MariaDB 的 upsert 更新可能计为两行。
`insert()` 仍返回 `Future<bool>`，空插入/upsert 输入仍被拒绝。`updateOrInsert()`
支持值 Map 或接收 `bool exists` 的同步/异步回调，返回是否有行被写入；空更新 Map
直接返回成功。`existsOr()` / `doesntExistOr()` 改为接收惰性回调，返回 `true`
或回调的结果，也支持异步回调。

### 聚合函数

`exists()` 和 `doesntExist()` 保留 GROUP BY 和 HAVING 条件。分组查询的 `count()`
返回组数，distinct 查询返回去重后的行数，UNION 查询统计完整联合结果。
分组后的 `sum`、`avg`、`min`、`max` 只返回第一组的聚合值；如需全部分组，
请选择聚合表达式并调用 `get()`。

```dart
final count = await laconic.table('users').count();
final total = await laconic.table('orders').sum('amount');
final average = await laconic.table('products').avg('price');
final highest = await laconic.table('scores').max('score');
final lowest = await laconic.table('scores').min('score');
```

### 插入 / 更新 / 删除

```dart
// 插入
await laconic.table('users').insert([
  {'name': 'John', 'age': 25},
]);

// 插入（忽略重复键错误）
await laconic.table('users').insertOrIgnore([
  {'email': 'john@example.com', 'name': 'John'},
]);

// 插入并获取 ID
final id = await laconic.table('users').insertGetId({
  'name': 'Jane',
  'age': 30,
});

// Upsert（冲突时插入或更新）
await laconic.table('users').upsert(
  [{'email': 'john@example.com', 'name': 'John Updated'}],
  uniqueBy: ['email'],
  update: ['name'],
);

// 更新（返回受影响行数）
final updated = await laconic.table('users')
    .where('id', 1)
    .update({'name': 'New Name'});

// 自增 / 自减（返回受影响行数）
final incremented =
    await laconic.table('posts').where('id', 1).increment('views');
final decremented = await laconic
    .table('products')
    .where('id', 1)
    .decrement('stock', amount: 5);

// 删除（返回受影响行数）
final deleted = await laconic.table('users')
    .where('id', 99)
    .delete();

// 清空表（删除所有行，重置自增 ID）
await laconic.table('logs').truncate();

// 注意：delete()、increment()、decrement() 默认需要 WHERE 子句

// 行锁（MySQL/PostgreSQL；在事务内使用）
final locked = await laconic.table('users')
    .where('status', 'pending')
    .lockForUpdate()   // FOR UPDATE（仅 MySQL/PostgreSQL）
    .get();

final shared = await laconic.table('users')
    .where('id', 5)
    .sharedLock()      // FOR SHARE (PG) / LOCK IN SHARE MODE (MySQL)
    .get();
```

### 排序和分页

```dart
final users = await laconic.table('users')
    .orderBy('name')
    .orderByDesc('created_at')      // orderBy(col, direction: 'desc') 的简写
    .latest()                        // orderByDesc('created_at')
    .oldest('updated_at')            // orderBy('updated_at')
    .inRandomOrder()                 // RANDOM() 排序
    .skip(10)                        // offset(10) 的别名
    .take(5)                         // limit(5) 的别名
    .forPage(3, perPage: 15)        // limit(15).offset(30)
    .get();
```

### UNION

`union()` 会去除重复行，`unionAll()` 保留重复行。每个分支保留选择列、过滤、
分组、HAVING 和分页；父构造器上的排序、limit 和 offset 作用于完整 UNION。
最终排序应使用输出列名，两侧分支必须选择兼容的列。
`get()`、`first()`、`sole()`、`value()`、`pluck()`、聚合、`exists()`、
`toSql()` 和 `getBindings()` 都会包含 UNION。

```dart
final results = await laconic.table('users')
    .where('role', 'admin')
    .union((q) => q.from('users').where('role', 'moderator'))
    .get();
```

### 子查询

```dart
// SELECT 子查询
final users = await laconic.table('users u')
    .select(['u.id'])
    .selectSub(
      (q) => q.from('posts p')
          .selectRaw('count(*)')
          .whereColumn('p.user_id', 'u.id'),
      'posts_count',
    )
    .get();

// FROM 子查询
final active = await laconic.table('users')
    .fromSub((q) => q.from('users').where('active', 1), 'u')
    .get();

// IN 子查询（回调或现成的 QueryBuilder）
final authors = await laconic.table('users')
    .whereIn('id', (q) => q.from('posts').select(['user_id']))
    .get();

// JOIN 子查询
final rows = await laconic.table('posts p')
    .select(['p.id', 'x.views'])
    .joinSub(
      (q) => q.from('post_stats').select(['post_id', 'views']),
      'x',
      'p.id',
      '=',
      'x.post_id',
    )
    .get();

// INSERT ... SELECT
await laconic.table('users_archive')
    .insertUsing(['id', 'name'], laconic.table('users').select(['id', 'name']));
```

### 分页与流式

游标分页保留完整的 `orderBy` 顺序，支持混合升降序。排序列组合必须唯一，且每个
排序值都必须被 SELECT 选出并非 NULL；可追加 `id` 作为唯一的排序依据。
`nextCursor` / `previousCursor` 现在为 `LaconicCursor?`，包含 `parameters` 和
`pointsToNextItems`。把任一游标传回同一排序查询即可前后翻页，返回数据始终保持原排序。
只有对应游标非空时才应翻页，传入 null 会回到第一页；空页不返回导航游标。
`hasMorePages` 表示后方还有页面，`hasPreviousPages` 表示前方还有页面。

单列查询仍接受旧的标量游标。未显式排序时，使用 `column:`（默认 `id`）升序。
`groupLimit` 的已有排序负责组内选行，`column:` 负责外层分页；需要复合外层排序时，
先用 `fromSub()` 包裹 groupLimit 查询。原始 ORDER BY 片段会被拒绝；表达式应先
SELECT 为别名，再 `orderBy(别名)`。别名、分组结果和 UNION 在外层过滤，保留结果集与绑定。

```dart
final page = await laconic.table('users').orderBy('id').paginate(2, perPage: 20);
page.data;
page.total;
page.lastPage;
page.hasMorePages;

final simple = await laconic.table('users').simplePaginate(2, perPage: 20);
final ordered = laconic.table('users').orderByDesc('created_at').orderBy('id');
final firstPage = await ordered.cursorPaginate(20);
if (firstPage.nextCursor != null) {
  final nextPage = await ordered.cursorPaginate(20, cursor: firstPage.nextCursor);
  if (nextPage.previousCursor != null) {
    final previousPage = await ordered.cursorPaginate(
      20, cursor: nextPage.previousCursor,
    );
  }
}

await for (final row in laconic.table('users').orderBy('id').cursor()) {
  print(row['name']);
}
await for (final row in laconic.table('users').orderBy('id').lazy(500)) {
  print(row['name']);
}
await for (final row in laconic.table('users').lazyById(500)) {
  print(row['name']);
}
```

### JSON、全文与方言方法

```dart
await laconic.table('users').whereJsonContains('tags', 'admin').get();
await laconic.table('users').whereJsonContains('profile->roles', 'admin').get();
await laconic.table('users').whereJsonContainsKey('profile->email').get();
await laconic.table('users').whereJsonLength('tags', 2).get();
await laconic.table('users').whereJsonOverlaps('tags', ['admin']).get();

await laconic.table('posts').whereFullText(['title', 'body'], 'dart').get();

await laconic.table('users').whereBinary('name', 'John').get(); // MySQL
await laconic.table('users').useIndex('idx_name').get();       // MySQL
await laconic.table('accounts').updateFrom('balances', {       // PostgreSQL
  'amount': Expression('balances.amount'),
});
```

具体可用性以各驱动 README 和 CHANGELOG 为准。

### 查询钩子

```dart
final laconic = Laconic(
  SqliteDriver(SqliteConfig('app.db')),
  beforeQuery: (query) => print('→ ${query.sql}'),
  afterQuery: (query, elapsed) =>
      print('← ${query.sql}（${elapsed.inMilliseconds} ms）'),
);
```

### 标识符、JSON 路径与写入范围

列名、表名、限定名称和别名会按数据库方言引用。SQL 表达式请使用 `Expression`、
`selectRaw`、`groupByRaw`、`havingRaw` 或 `fromRaw`；`COUNT(*)` 这样的普通字符串
现在会被视为列名。普通条件、查询列和更新键均支持 JSON 路径：

```dart
await laconic.table('users').where('settings->enabled', true).update({
  'settings->name': 'Alice',
  'settings->notifications->email': false,
});
final names = await laconic.table('users').pluck('settings->name');
```

`update`、`delete` 和增减操作会保留方言支持的 JOIN、排序、LIMIT 和 OFFSET。
MySQL/MariaDB 拒绝非零写入 OFFSET，以及 JOIN 与排序/LIMIT 的组合；MariaDB 10.11
带表别名的 DELETE 也不支持排序/LIMIT。SQL Server
支持 JOIN 和 TOP 限制，拒绝排序写入及非零 OFFSET。SQLite 用 rowid、PostgreSQL
用行标识子查询限定目标行，因此 SQLite 的这类写入需要 rowid 表。
分组、HAVING、UNION、DISTINCT、派生/原始 FROM、`groupLimit`、索引提示和锁
用于写入时会报错，不再被忽略。`updateOrInsert` 最多更新一条匹配记录。

### 大数据集分块处理

`chunkById` 按唯一、非 null 的游标列升序读取，默认列为 `id`。它会替换已有排序，
初始 offset 只作用于第一批，且查询结果必须包含游标列。
`column` 指定 SQL 游标列（如 `u.id`），`alias` 指定查询结果中的列名（如 `cursor_id`）。游标过滤覆盖原有 OR 条件和完整 UNION。
所有分块大小必须为正数。`chunk()` 和 `each()` 使用 OFFSET 分页，
`chunkById()` 使用上一批最后一行的游标值继续读取。`chunk`、`each` 和 `lazy`
需要显式 `orderBy`。分块读取保留总 LIMIT 和初始 OFFSET，且不修改原查询。
`chunk`/`chunkById` 回调接受 `(rows)` 或 `(rows, page)`，页码从 1 开始；
`each`/`eachById` 接受 `(row)` 或 `(row, index)`，索引从 0 开始。
回调可同步或异步，返回 `false` 提前停止；这些方法正常完成返回 `true`，提前停止返回
`false`。现有单参数异步回调仍可使用。

```dart
// 每次处理 100 条记录
await laconic.table('users').orderBy('id').chunk(100, (users) async {
  for (final user in users) {
    await processUser(user);
  }
});

// 基于 ID 的分块（避免大 OFFSET）
await laconic.table('users').chunkById(100, (users) async {
  // ...
});

// 逐行回调（自动分块）
await laconic.table('users').orderBy('id').each((user) async {
  await sendWelcomeEmail(user['email']);
});

// 克隆构建器以复用查询条件
final activeQuery = laconic.table('users').where('active', true);
final count = await activeQuery.clone().count();
final results = await activeQuery.clone().get();
```

### 事务

在事务回调中等待所有查询完成。MySQL 和 PostgreSQL 按驱动实例固定事务连接或会话，
通过另一驱动发起的查询仍使用另一驱动自己的连接。SQLite 会在单连接上排队执行
重叠事务及无关查询。同一驱动实例的嵌套事务抛出 `LaconicException`，不会自动创建 savepoint。

```dart
await laconic.transaction(() async {
  final userId = await laconic.table('users').insertGetId({
    'name': 'Test User',
  });

  await laconic.table('posts').insert([
    {'user_id': userId, 'title': 'First Post'},
  ]);
});
```

## 架构

### 包结构

```
laconic/                     # 工作区根目录
├── packages/
│   ├── laconic/             # 核心包
│   │   └── lib/src/
│   │       ├── laconic.dart          # 主入口
│   │       ├── database_driver.dart  # 抽象驱动接口
│   │       ├── grammar/              # SQL 语法（抽象）
│   │       └── query_builder/        # 查询构建器
│   ├── laconic_sqlite/      # SQLite 驱动
│   ├── laconic_mysql/       # MySQL 驱动
│   └── laconic_postgresql/  # PostgreSQL 驱动
```

### 核心组件

1. **Laconic** - 主入口，委托给驱动
2. **DatabaseDriver** - 数据库驱动的抽象接口
3. **SqlGrammar** - SQL 生成的抽象基类
4. **QueryBuilder** - 流畅查询构建器

### 自定义驱动

你可以通过实现 `DatabaseDriver` 来创建自定义驱动：

```dart
class MyDriver implements DatabaseDriver {
  @override
  SqlGrammar get grammar => MyGrammar();

  @override
  Future<List<LaconicResult>> select(String sql, [List<Object?> params = const []]) async {
    // 实现
  }

  // 实现其他方法...
}
```

## 测试

从 workspace 根目录运行。核心包和 SQLite 测试无需 Docker；MySQL/PostgreSQL
测试使用 `docker-compose.yml` 中的本地测试库（端口分别为 3306 和 5433）。

```bash
dart pub get
dart analyze

# 无需 Docker 的测试
dart test packages/laconic/test packages/laconic_sqlite/test

# 启动并等待数据库健康，再运行四个包的完整测试
docker compose up -d --wait
dart test packages/laconic/test packages/laconic_sqlite/test packages/laconic_mysql/test packages/laconic_postgresql/test --concurrency=1
docker compose down
```

覆盖查询语义、重复列名、分片接收、TLS 大结果、并发命令、事务隔离和服务端语句缓存释放。

## 升级到当前版本

- 核心包为 `6.0.0`，MySQL 驱动为 `5.0.0`，SQLite/PostgreSQL 驱动为 `4.0.0`；请一起更新核心包和所用驱动。
- 已发布的 6.0 使用 `num?` 聚合返回值；当前未发布版本的返回值变化见上文。
- `insert()` 返回 `Future<bool>`。
- `where('column', null)` 现在编译为 `IS NULL`，而不是 `= NULL`。
- 自定义语法若覆盖 `SqlGrammar.compileSelect`，必须补上新增的可选参数（`selectBindings`、`groupBindings`、`distinctColumns`、`fromSubquery`、`fromAlias`、`indexHints`）。
- 自定义驱动若使用 `implements DatabaseDriver`，必须实现 `selectStream`；默认实现会缓冲 `select()`。
- 新增分页/流式、子查询、JSON/全文、`groupLimit`、查询钩子及上表列出的方言方法。
- `first()` / `find()` 语义不变（空结果抛异常）；需要可空结果请用 `firstOrNull()` / `findOrNull()`。

发布记录：[核心包](packages/laconic/CHANGELOG.md)、[SQLite](packages/laconic_sqlite/CHANGELOG.md)、[MySQL](packages/laconic_mysql/CHANGELOG.md)、[PostgreSQL](packages/laconic_postgresql/CHANGELOG.md)。发布步骤见 [RELEASE.md](RELEASE.md)。

## 从 1.x 迁移

之前（1.x）：
```dart
import 'package:laconic/laconic.dart';
final laconic = Laconic.mysql(MysqlConfig(...));
```

之后（2.0 及更高版本）：
```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
final laconic = Laconic(MysqlDriver(MysqlConfig(...)));
```

## 许可证

MIT License

## 贡献

欢迎提交 Issues 和 Pull Requests！

## Schema 与迁移（未发布）

已支持 MySQL/MariaDB 与 PostgreSQL 全文索引、索引重命名和删除、列注释/排序规则、
时间修饰及生成列；各数据库的支持范围和第三方驱动升级要求见 SCHEMA.md。

支持 `change()`、表/视图/列/索引/外键的类型化元数据，以及 SQLite 原子重建；
事务限制与方言差异见 Schema 指南。
Blueprint 已补外键、软删除和 morphs 快捷方法，以及枚举/集合、JSONB/ULID、
时间、二进制、网络和空间类型；支持范围以方言矩阵为准。

核心新增 `db.schema`，用于建表、改表和结构检查。DDL 统一由现有 `SqlGrammar` 编译，
具体方言仍在各驱动包内。详见 [Schema Builder 与驱动扩展](SCHEMA.md)，
以及内置的 [Migration 与 CLI](packages/laconic/MIGRATIONS.md)。
`Migration`、`Migrator` 直接从核心包导入，CLI 使用 `dart run laconic`。
CLI 已支持 reset/refresh/fresh、按批次回滚、SQL 预览和生产环境 `--force` 保护。
