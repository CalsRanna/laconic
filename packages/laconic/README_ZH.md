# Laconic

一个 Laravel 风格的 Dart SQL 查询构建器，支持 MySQL、SQLite 和 PostgreSQL 数据库。

这是核心包，提供查询构建器 API 和抽象驱动接口。你还需要安装对应数据库的驱动包：

- [laconic_sqlite](https://pub.dev/packages/laconic_sqlite) - SQLite 驱动
- [laconic_mysql](https://pub.dev/packages/laconic_mysql) - MySQL 驱动
- [laconic_postgresql](https://pub.dev/packages/laconic_postgresql) - PostgreSQL 驱动

## 特性

- **Laravel 风格 API** - 熟悉的查询构建器语法，57 个方法
- **流畅接口** - 链式方法优雅构建查询
- **参数化查询** - 自动防止 SQL 注入
- **事务支持** - 完整的事务管理
- **查询监听器** - 内置调试和日志功能
- **驱动抽象** - 查询构建器与数据库实现清晰分离

## 安装

```yaml
dependencies:
  laconic: ^2.0.0
  laconic_sqlite: ^1.0.0  # 或其他驱动
```

## 快速开始

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

## 查询构建器

### 查询

```dart
// 获取所有记录
final users = await laconic.table('users').get();

// 获取第一条记录（无结果时抛出异常）
final user = await laconic.table('users').first();

// 获取唯一记录（无结果或多条结果时抛出异常）
final user = await laconic.table('users').where('email', 'john@example.com').sole();

// 选择特定列
final names = await laconic.table('users').select(['name', 'age']).get();

// 去重
final roles = await laconic.table('users').distinct().select(['role']).get();
```

### WHERE 子句

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

// 列对比
final users = await laconic.table('users')
    .whereColumn('created_at', 'updated_at', operator: '<')
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

// RIGHT JOIN
final results = await laconic.table('users u')
    .rightJoin('posts p', (join) => join.on('u.id', 'p.user_id'))
    .get();

// CROSS JOIN
final results = await laconic.table('users')
    .crossJoin('roles')
    .get();
```

### 聚合函数

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

// 插入并获取 ID
final id = await laconic.table('users').insertGetId({
  'name': 'Jane',
  'age': 30,
});

// 更新
await laconic.table('users')
    .where('id', 1)
    .update({'name': 'New Name'});

// 自增 / 自减
await laconic.table('posts').where('id', 1).increment('views');
await laconic.table('products').where('id', 1).decrement('stock', amount: 5);

// 删除
await laconic.table('users')
    .where('id', 99)
    .delete();

// 注意：delete()、increment()、decrement() 默认需要 WHERE 子句，
// 以防止意外的批量操作。如需显式允许无 WHERE 操作：
// await laconic.table('users').delete(allowWithoutWhere: true);
```

### 排序和分页

```dart
final users = await laconic.table('users')
    .orderBy('name')
    .orderByDesc('created_at')
    .limit(10)
    .offset(20)
    .get();
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

## 自定义驱动

你可以通过实现 `DatabaseDriver` 来创建自定义驱动：

```dart
class MyDriver implements DatabaseDriver {
  @override
  SqlGrammar get grammar => MyGrammar();

  @override
  Future<List<LaconicResult>> select(String sql, [List<Object?> params = const []]) async {
    // 实现
  }

  @override
  Future<void> statement(String sql, [List<Object?> params = const []]) async {
    // 实现
  }

  @override
  Future<int> insertAndGetId(String sql, [List<Object?> params = const []]) async {
    // 实现
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) async {
    // 实现
  }

  @override
  Future<void> close() async {
    // 实现
  }
}
```

## 许可证

MIT License
