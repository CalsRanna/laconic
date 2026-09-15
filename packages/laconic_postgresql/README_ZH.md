# laconic_postgresql

[Laconic](https://pub.dev/packages/laconic) 查询构建器的 PostgreSQL 驱动。

## 安装

```yaml
dependencies:
  laconic: ^3.0.0
  laconic_postgresql: ^2.0.0
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

PostgreSQL 驱动内部使用连接池以提升性能。连接会自动管理，每次查询后释放回池中。

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

## 参数绑定

PostgreSQL 使用编号占位符（`$1`、`$2`、...）而不是 `?`。驱动会自动处理这个转换，因此你可以使用与其他数据库相同的查询构建器 API。

## 许可证

MIT License

## 原始 SQL 参数

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

预编译语句按物理连接缓存，每个连接最多 50 条，淘汰时释放服务端资源。
事务拥有单独的会话缓存，事务结束时释放。不同驱动实例的事务相互独立；
同一个驱动实例不支持嵌套事务。
