# laconic_sqlite

[Laconic](https://pub.dev/packages/laconic) 查询构建器的 SQLite 驱动。

## 安装

```yaml
dependencies:
  laconic: ^2.0.0
  laconic_sqlite: ^1.0.0
```

## 使用

```dart
import 'package:laconic/laconic.dart';
import 'package:laconic_sqlite/laconic_sqlite.dart';

void main() async {
  // 创建文件数据库
  final laconic = Laconic(SqliteDriver(SqliteConfig('app.db')));

  // 或使用内存数据库
  // final laconic = Laconic(SqliteDriver(SqliteConfig(':memory:')));

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

`SqliteConfig` 接受一个参数：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | `String` | SQLite 数据库文件路径。使用 `:memory:` 创建内存数据库。 |

## 查询监听器

可以添加查询监听器用于调试：

```dart
final laconic = Laconic(
  SqliteDriver(SqliteConfig('app.db')),
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
