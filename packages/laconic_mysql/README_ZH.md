# laconic_mysql

[Laconic](https://pub.dev/packages/laconic) 查询构建器的 MySQL 驱动。

[English](README.md)

## 安装

```yaml
dependencies:
  laconic: ^3.0.0
  laconic_mysql: ^2.1.0
```

## 使用

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
    // maxConnections: 10, // 可选，默认 10
  )));

  // 查询用户
  final users = await laconic.table('users').where('active', true).get();

  // 插入数据
  final id = await laconic.table('users').insertGetId({
    'name': 'John',
    'age': 25,
  });

  // 更新数据并获取 WHERE 条件匹配的行数
  final updated =
      await laconic.table('users').where('id', id).update({'age': 26});

  // 删除数据并获取受影响行数
  final deleted = await laconic.table('users').where('id', id).delete();

  // 别忘了关闭连接
  await laconic.close();
}
```

## 配置

`MysqlConfig` 接受以下参数：

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `database` | `String` | 必填 | 数据库名 |
| `host` | `String` | `'127.0.0.1'` | MySQL 主机地址 |
| `port` | `int` | `3306` | 连接端口 |
| `username` | `String` | `'root'` | 用户名 |
| `password` | `String` | 必填 | 密码 |
| `maxConnections` | `int` | `10` | 连接池最大连接数 |

## 连接池

驱动内部维护轻量连接池：

- 首次查询时惰性创建连接
- 非事务查询借用连接后**始终**归还（**包括 SQL 抛错时**）
- 事务通过 Zone 在回调期间固定同一连接
- 应用退出时调用 `close()` 关闭连接池

这样可避免连续查询失败导致连接槽位耗尽、后续请求永久等待。

## UPDATE 返回值

MySQL 更新采用“匹配行数”语义。只要 `WHERE` 条件匹配到一行，即使提交的值
与数据库现有值完全相同，也返回 `1`；原记录不存在时返回 `0`。调用方因此可以
区分“记录存在但数据未变化”和“记录已被并发删除”。

本包将维护的 MySQL 客户端 fork 作为私有实现直接内嵌，应用无需额外依赖或
覆盖 `mysql_client`。

## 查询监听器

可以添加查询监听器用于调试：

```dart
final laconic = Laconic(
  MysqlDriver(MysqlConfig(
    database: 'my_database',
    password: 'password',
  )),
  listen: (query) {
    print('SQL: ${query.sql}');
    print('Bindings: ${query.bindings}');
  },
);
```

## 事务

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

## 许可证

MIT License
