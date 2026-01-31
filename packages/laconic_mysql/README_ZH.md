# laconic_mysql

[Laconic](https://pub.dev/packages/laconic) 查询构建器的 MySQL 驱动。

## 安装

```yaml
dependencies:
  laconic: ^2.0.0
  laconic_mysql: ^1.0.0
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

`MysqlConfig` 接受以下参数：

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `database` | `String` | 必填 | 数据库名 |
| `host` | `String` | `'127.0.0.1'` | MySQL 主机地址 |
| `port` | `int` | `3306` | 连接端口 |
| `username` | `String` | `'root'` | 用户名 |
| `password` | `String` | 必填 | 密码 |

## 连接池

MySQL 驱动内部使用连接池以提升性能。连接会自动管理，每次查询后释放回池中。

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
