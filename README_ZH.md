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

```dart
final page = await laconic.table('users').orderBy('id').paginate(2, perPage: 20);
page.data;
page.total;
page.lastPage;
page.hasMorePages;

final simple = await laconic.table('users').simplePaginate(2, perPage: 20);
final cursor = await laconic.table('users').cursorPaginate(20);
final next = await laconic.table('users').cursorPaginate(
  20,
  cursor: cursor.nextCursor,
);

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
  'amount': raw('balances.amount'),
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

### 大数据集分块处理

`chunkById` 按唯一、非 null 的游标列升序读取，默认列为 `id`。它会替换已有排序，
初始 offset 只作用于第一批，且查询结果必须包含游标列。
`column` 指定游标列，`alias` 用于添加表别名前缀。游标过滤覆盖原有 OR 条件和完整 UNION。
所有分块大小必须为正数。`chunk()` 和 `each()` 使用 OFFSET 分页，
`chunkById()` 使用上一批最后一行的游标值继续读取。

```dart
// 每次处理 100 条记录
await laconic.table('users').chunk(100, (users) async {
  for (final user in users) {
    await processUser(user);
  }
});

// 基于 ID 的分块（避免大 OFFSET）
await laconic.table('users').chunkById(100, (users) async {
  // ...
});

// 逐行回调（自动分块）
await laconic.table('users').each((user) async {
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
- `sum()`、`max()`、`min()` 返回 `num?`；`avg()` 仍为 `double?`。
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
