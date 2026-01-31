# laconic_postgresql

[Laconic](https://pub.dev/packages/laconic) 查询构建器的 PostgreSQL 驱动。

## 安装

```yaml
dependencies:
  laconic: ^2.0.0
  laconic_postgresql: ^1.0.0
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

  // 更新数据
  await laconic.table('users').where('id', id).update({'age': 26});

  // 删除数据
  await laconic.table('users').where('id', id).delete();

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
