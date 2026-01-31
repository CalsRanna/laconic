# Laconic

<p align="right">
  <a href="README.md">English</a> | <a href="README_ZH.md">简体中文</a>
</p>

一个 Laravel 风格的 Dart SQL 查询构建器，支持 MySQL、SQLite 和 PostgreSQL 数据库。提供流畅的链式 API 来优雅地构建数据库查询。

## 特性

- **Laravel 风格 API** - 熟悉的查询构建器语法，57 个方法覆盖 Laravel Query Builder 约 75% 的核心功能
- **多数据库支持** - 通过独立驱动包支持 MySQL、SQLite 和 PostgreSQL
- **驱动抽象** - 核心查询构建器与数据库实现清晰分离
- **完整 JOIN 支持** - INNER、LEFT、RIGHT、CROSS JOIN 及全面的条件方法
- **链式方法** - 流畅的查询构建体验
- **参数化查询** - 自动防止 SQL 注入
- **事务支持** - 完整的事务管理
- **查询监听器** - 内置调试和日志功能

## 包

| 包 | 描述 | 版本 |
|---|------|------|
| [laconic](https://pub.dev/packages/laconic) | 核心查询构建器 | 2.0.0 |
| [laconic_sqlite](https://pub.dev/packages/laconic_sqlite) | SQLite 驱动 | 1.0.0 |
| [laconic_mysql](https://pub.dev/packages/laconic_mysql) | MySQL 驱动 | 1.0.0 |
| [laconic_postgresql](https://pub.dev/packages/laconic_postgresql) | PostgreSQL 驱动 | 1.0.0 |

## 安装

添加核心包和你需要的驱动：

```yaml
dependencies:
  laconic: ^2.0.0
  laconic_sqlite: ^1.0.0    # SQLite
  # laconic_mysql: ^1.0.0   # MySQL
  # laconic_postgresql: ^1.0.0  # PostgreSQL
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

// 获取第一条记录
final user = await laconic.table('users').first();

// 选择特定列
final names = await laconic.table('users').select(['name', 'age']).get();

// 统计记录数
final count = await laconic.table('users').count();

// 检查记录是否存在
final exists = await laconic.table('users').where('id', 1).exists();
```

### WHERE 子句

```dart
// 基本 where
final adults = await laconic.table('users')
    .where('age', 18, operator: '>=')
    .get();

// 多条件（AND）
final results = await laconic.table('users')
    .where('age', 18, operator: '>')
    .where('status', 'active')
    .get();

// OR 条件
final users = await laconic.table('users')
    .where('role', 'admin')
    .orWhere('role', 'moderator')
    .get();

// WHERE IN
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
```

### JOIN 操作

```dart
// INNER JOIN
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// 带条件的 LEFT JOIN
final results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .leftJoin(
      'posts p',
      (join) => join
          .on('u.id', 'p.user_id')
          .where('p.status', 'published'),
    )
    .get();
```

### 插入 / 更新 / 删除

```dart
// 插入
await laconic.table('users').insert([
  {'name': 'John', 'age': 25},
]);

// 插入并获取 ID
final id = await laconic.table('users').insertGetId({
  'name': 'Jane',
  'age': 30,
});

// 更新
await laconic.table('users')
    .where('id', 1)
    .update({'name': 'New Name'});

// 删除
await laconic.table('users')
    .where('id', 99)
    .delete();
```

### 事务

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

```bash
# 运行所有测试
dart test

# 运行特定包的测试
dart test packages/laconic/test
dart test packages/laconic_sqlite/test
dart test packages/laconic_mysql/test
dart test packages/laconic_postgresql/test

# 启动 Docker 容器进行 MySQL/PostgreSQL 测试
docker-compose up -d
dart test
docker-compose down
```

## 从 1.x 迁移

之前（1.x）：
```dart
import 'package:laconic/laconic.dart';
final laconic = Laconic.mysql(MysqlConfig(...));
```

之后（2.0）：
```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_mysql/laconic_mysql.dart';
final laconic = Laconic(MysqlDriver(MysqlConfig(...)));
```

## 许可证

MIT License

## 贡献

欢迎提交 Issues 和 Pull Requests！
