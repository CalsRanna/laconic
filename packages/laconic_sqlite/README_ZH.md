# laconic_sqlite

[English](README.md)

[Laconic](https://pub.dev/packages/laconic) 查询构建器的 SQLite 驱动。

## 安装

当前 workspace 解析的 `sqlite3 3.3.4` 需要 Dart 3.10 或更高的 3.x SDK，
高于本包声明的 Dart 3.7 最低版本。

```yaml
dependencies:
  laconic: ^5.0.0
  laconic_sqlite: ^3.0.0
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

在事务回调中等待所有查询完成。同一驱动实例不支持嵌套事务，嵌套调用会抛出
`LaconicException`；不会自动创建 savepoint。不同驱动实例使用各自的事务上下文。

事务在驱动的单连接上独占执行。重叠事务和事务外查询会等待当前事务结束；失败回滚
只影响当前事务中执行的写入。事务结束后，从该事务上下文继续发起的查询会被拒绝。

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

## 连接与性能

连接在首次使用时打开。每个驱动缓存最多 50 条预编译语句，淘汰或关闭驱动时释放；
通过 `statement()` 执行的 schema 变更会清理缓存。`insertGetId()` 使用原生
last-insert-ID getter，结果转换直接构建值列表并共享列元数据。

虽然接口返回 `Future`，SQLite 查询仍在调用方 isolate 内同步执行；长查询需要由应用
自行安排到工作 isolate。SQLite 不支持 `FOR UPDATE` 或 `FOR SHARE` 行锁子句。
应用结束时调用 `close()` 释放语句和数据库连接。

## 从 2.x 升级到 3.0

- 与 `laconic: ^5.0.0` 一起安装，应用采用核心包 5.0 的 UNION 和游标分页约定。
- 同实例嵌套事务会明确报错；重叠事务及无关查询会排队，避免混入当前事务。
- 结果的 `columns` 和 `values` 仍可修改。
- 完整发布记录见 [CHANGELOG](CHANGELOG.md)。

## 许可证

MIT License
