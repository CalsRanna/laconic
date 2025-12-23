# Laconic

<p align="right">
  <a href="README.md">简体中文</a> | <a href="README_EN.md">English</a>
</p>

一个为 Dart 设计的 Laravel 风格 SQL 查询构建器，支持 MySQL、SQLite 和 PostgreSQL 数据库。提供流畅的链式 API，让数据库查询变得简洁优雅。

## 特性

- **Laravel 风格 API** - 熟悉的查询构建器语法
- **多数据库支持** - 支持 MySQL、SQLite 和 PostgreSQL
- **链式调用** - 流畅的查询构建体验
- **参数化查询** - 自动防止 SQL 注入
- **事务支持** - 完整的事务管理
- **查询监听** - 内置调试和日志功能

## 安装

在 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  laconic: ^1.0.0
```

然后运行：

```bash
dart pub get
```

## 快速开始

### 数据库连接

#### MySQL

```dart
import 'package:laconic/laconic.dart';

var config = MysqlConfig(
  database: 'my_database',
  host: '127.0.0.1',
  port: 3306,
  username: 'root',
  password: 'password',
);

var laconic = Laconic.mysql(config);
```

#### SQLite

```dart
import 'package:laconic/laconic.dart';

var config = SqliteConfig('database.db');
var laconic = Laconic.sqlite(config);
```

#### PostgreSQL

```dart
import 'package:laconic/laconic.dart';

var config = PostgresqlConfig(
  database: 'my_database',
  host: '127.0.0.1',
  port: 5432,
  username: 'postgres',
  password: 'password',
);

var laconic = Laconic.postgresql(config);
```

### 查询监听（调试用）

```dart
var laconic = Laconic.mysql(
  config,
  listen: (query) {
    print('SQL: ${query.sql}');
    print('参数: ${query.bindings}');
  },
);
```

## 基本用法

### 原生 SQL 查询

```dart
// SELECT 查询
var users = await laconic.select('SELECT * FROM users WHERE age > ?', [18]);

// INSERT/UPDATE/DELETE 语句
await laconic.statement(
  'INSERT INTO users (name, age) VALUES (?, ?)',
  ['张三', 25],
);
```

### 查询构建器

#### 基本查询

```dart
// 获取所有记录
var users = await laconic.table('users').get();

// 获取第一条记录
var user = await laconic.table('users').first();

// 选择特定列
var names = await laconic.table('users').select(['name', 'age']).get();

// 统计记录数
var count = await laconic.table('users').count();

// 检查记录是否存在
var exists = await laconic.table('users').where('id', 1).exists();
```

#### WHERE 条件

```dart
// 基本条件
var adults = await laconic.table('users')
    .where('age', 18, comparator: '>=')
    .get();

// 多条件 (AND)
var results = await laconic.table('users')
    .where('age', 18, comparator: '>')
    .where('status', 'active')
    .get();

// OR 条件
var users = await laconic.table('users')
    .where('role', 'admin')
    .orWhere('role', 'moderator')
    .get();

// WHERE IN
var users = await laconic.table('users')
    .whereIn('id', [1, 2, 3])
    .get();

// WHERE NOT IN
var users = await laconic.table('users')
    .whereNotIn('status', ['banned', 'deleted'])
    .get();

// WHERE NULL / NOT NULL
var usersWithEmail = await laconic.table('users')
    .whereNotNull('email')
    .get();

var usersWithoutEmail = await laconic.table('users')
    .whereNull('email')
    .get();

// WHERE BETWEEN
var users = await laconic.table('users')
    .whereBetween('age', min: 18, max: 30)
    .get();

// WHERE NOT BETWEEN
var users = await laconic.table('users')
    .whereNotBetween('age', min: 18, max: 30)
    .get();

// 列对比
var users = await laconic.table('users')
    .whereColumn('created_at', 'updated_at', operator: '<')
    .get();

// 所有列必须匹配
var users = await laconic.table('users')
    .whereAll(['name', 'email'], '%john%', operator: 'like')
    .get();

// 任一列匹配
var users = await laconic.table('users')
    .whereAny(['name', 'email', 'phone'], 'john', operator: 'like')
    .get();

// 所有列都不匹配
var users = await laconic.table('users')
    .whereNone(['name', 'email'], '%spam%', operator: 'like')
    .get();
```

#### JOIN 操作

```dart
// 基本 JOIN
var results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// 多条件 JOIN
var results = await laconic.table('users u')
    .select(['u.name', 'p.title'])
    .join(
      'posts p',
      (join) => join
          .on('u.id', 'p.user_id')
          .orOn('u.email', 'p.author_email')
          .where('p.status', 'published'),
    )
    .get();
```

#### 排序、分组和分页

```dart
// 排序
var users = await laconic.table('users')
    .orderBy('name')
    .orderBy('age', direction: 'desc')
    .get();

// 分组
var counts = await laconic.table('posts')
    .select(['user_id'])
    .groupBy('user_id')
    .having('user_id', 1, operator: '>')
    .get();

// 去重
var ages = await laconic.table('users')
    .select(['age'])
    .distinct()
    .get();

// 分页
var users = await laconic.table('users')
    .limit(10)
    .offset(20)
    .get();
```

#### 聚合函数

```dart
// 平均值
var avgAge = await laconic.table('users').avg('age');

// 求和
var totalAge = await laconic.table('users').sum('age');

// 最大值
var maxAge = await laconic.table('users').max('age');

// 最小值
var minAge = await laconic.table('users').min('age');

// 带条件的聚合
var avgMaleAge = await laconic.table('users')
    .where('gender', 'male')
    .avg('age');
```

### 插入数据

```dart
// 插入单条记录
await laconic.table('users').insert([
  {'name': '张三', 'age': 25, 'gender': 'male'},
]);

// 插入多条记录
await laconic.table('users').insert([
  {'name': '李四', 'age': 30, 'gender': 'male'},
  {'name': '王五', 'age': 28, 'gender': 'female'},
]);

// 插入并获取 ID
var id = await laconic.table('users').insertGetId({
  'name': '赵六',
  'age': 22,
  'gender': 'male',
});
print('新用户 ID: $id');
```

### 更新数据

```dart
// 基本更新
await laconic.table('users')
    .where('id', 1)
    .update({'name': '新名字'});

// 批量更新
await laconic.table('users')
    .where('status', 'pending')
    .update({'status': 'active'});

// 自增
await laconic.table('users')
    .where('id', 1)
    .increment('login_count');

// 自增指定数值
await laconic.table('users')
    .where('id', 1)
    .increment('points', amount: 10);

// 自增同时更新其他列
await laconic.table('users')
    .where('id', 1)
    .increment(
      'age',
      extra: {'updated_at': DateTime.now().toIso8601String()},
    );

// 自减
await laconic.table('users')
    .where('id', 1)
    .decrement('balance', amount: 100);
```

### 删除数据

```dart
// 条件删除
await laconic.table('users')
    .where('id', 99)
    .delete();

// 批量删除
await laconic.table('users')
    .where('status', 'inactive')
    .delete();
```

### 实用方法

```dart
// pluck - 获取单列值数组
var names = await laconic.table('users').pluck('name') as List<Object?>;

// pluck - 获取键值对 Map
var idNameMap = await laconic.table('users').pluck('name', key: 'id')
    as Map<Object?, Object?>;

// value - 获取单个值
var name = await laconic.table('users')
    .where('id', 1)
    .value('name');

// addSelect - 追加选择列
var users = await laconic.table('users')
    .select(['name'])
    .addSelect(['age', 'email'])
    .get();

// when - 条件构建
var role = 'admin';
var users = await laconic.table('users')
    .when(
      role == 'admin',
      (query) => query.where('is_admin', true),
      otherwise: (query) => query.where('is_active', true),
    )
    .get();

// sole - 确保只有一条结果
try {
  var user = await laconic.table('users')
      .where('email', 'unique@example.com')
      .sole();
} catch (e) {
  print('结果不唯一或不存在');
}
```

### 事务

```dart
try {
  await laconic.transaction(() async {
    // 插入用户
    var userId = await laconic.table('users').insertGetId({
      'name': '测试用户',
      'age': 30,
    });

    // 插入关联数据
    await laconic.table('posts').insert([
      {'user_id': userId, 'title': '第一篇文章'},
    ]);

    // 如果任何操作失败，整个事务将回滚
  });
  print('事务成功');
} catch (e) {
  print('事务失败: $e');
}
```

### 关闭连接

```dart
// 完成后记得关闭连接
await laconic.close();
```

## 架构概览

### 核心组件

1. **Laconic** - 主入口点，管理数据库连接
2. **QueryBuilder** - 流畅的查询构建器
3. **Grammar** - SQL 生成核心（使用 Grammar 模式）
4. **JoinClause** - JOIN 条件构建器

### 设计模式

- **Grammar 模式**：QueryBuilder 收集查询组件，Grammar 负责编译成具体 SQL
- **参数绑定**：所有查询使用参数化绑定（`?`）防止 SQL 注入
- **延迟连接**：数据库连接在首次使用时才建立

## 依赖

- `mysql_client: ^0.0.27` - MySQL 连接
- `sqlite3: ^2.7.5` - SQLite 支持
- `postgres: ^3.5.5` - PostgreSQL 支持

## 测试

```bash
# 运行所有测试
dart test

# 运行特定测试
dart test --name "test_name"
```

## 许可证

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！
