# laconic_postgresql

[English](README.md)

[Laconic](https://pub.dev/packages/laconic) 查询构建器的 PostgreSQL 驱动。

## 安装

本包声明 Dart SDK `>=3.7.0 <4.0.0`；当前解析的 `postgres 3.5.9` 需要 Dart 3.9
或更高版本。运行完整 workspace 时还需满足 SQLite 依赖的 Dart 3.10 要求。

```yaml
dependencies:
  laconic: ^5.0.0
  laconic_postgresql: ^3.0.0
```

## 使用

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

  // 查询用户
  final users = await laconic.table('users').where('active', true).get();

  // 插入数据
  final id = await laconic.table('users').insertGetId({
    'name': 'John',
    'age': 25,
  });

  // 更新数据并获取受影响行数
  final updated =
      await laconic.table('users').where('id', id).update({'age': 26});

  // 删除数据并获取受影响行数
  final deleted = await laconic.table('users').where('id', id).delete();

  // 别忘了关闭连接
  await laconic.close();
}
```

## 配置

`PostgresqlConfig` 接受以下参数：

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `database` | `String` | 必填 | 数据库名 |
| `host` | `String` | `'127.0.0.1'` | PostgreSQL 主机地址 |
| `port` | `int` | `5432` | 连接端口 |
| `username` | `String` | `'postgres'` | 用户名 |
| `password` | `String` | 必填 | 密码 |
| `useSsl` | `bool` | `true` | 是否使用 SSL 连接 |

## 连接池

连接池在首次使用时创建，最多 10 个连接。事务外查询借用连接，完成后归还；
事务在整个回调期间持有同一连接。预编译语句按可复用的物理连接缓存，每连接最多 50 条。
淘汰或执行报错时释放语句，连接关闭时清理缓存元数据。事务使用单独的会话缓存，
在提交或回滚前释放。应用结束时调用 `close()` 关闭连接池。

## 查询监听器

可以添加查询监听器用于调试：

```dart
final laconic = Laconic(
  PostgresqlDriver(PostgresqlConfig(
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

在事务回调中等待所有查询完成。同一驱动实例不支持嵌套事务，嵌套调用会抛出
`LaconicException`；不会自动创建 savepoint。不同驱动实例使用各自的事务上下文。

事务内查询固定到同一连接或会话并串行执行。可以等待 `Future.wait` 中的多个查询，
每个查询仍接收自己的结果；通过另一驱动实例发起的查询使用另一实例的连接。

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

## 参数绑定与原始 SQL

原始子句和驱动查询支持 `?` 或 PostgreSQL 原生 `$1`、`$2` 等占位符。
每个原始子句中的 `$N` 从本地 `$1` 开始编号，组合完整查询时自动偏移；
重复的 `$1` 复用同一个绑定。单个子句混用两种形式时，`?` 排在最大原生编号之后。
绑定列表长度必须与这些参数位置匹配。

```dart
await laconic.table('users').where('active', true)
    .whereRaw(r'id = $1', [7]).get();
await laconic.select('SELECT ?::jsonb ? ? AS found', ['{"key":1}', 'key']);
```

字符串、带引号的标识符、注释和 dollar quote 中的问号保持原样。
支持保留 PostgreSQL 的 `?`、`?|`、`?&`、`@?` JSON 运算符，
也可以用 `??` 显式表示问号运算符。

占位符转换采用单次扫描，结果行直接构建值列表并共享列元数据。

## 从 2.x 升级到 3.0

- 与 `laconic: ^5.0.0` 一起安装，应用采用核心包 5.0 的 UNION 和游标分页约定。
- 原始 SQL 参数严格按上述规则编号并验证数量；引用字符串内的问号不会被替换。
- 同实例嵌套事务会明确报错，跨实例调用保留各自的连接和事务归属。
- 完整发布记录见 [CHANGELOG](CHANGELOG.md)。

## 许可证

MIT License
