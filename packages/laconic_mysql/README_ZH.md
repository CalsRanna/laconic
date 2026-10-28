# laconic_mysql

[Laconic](https://pub.dev/packages/laconic) 查询构建器的 MySQL 驱动。

[English](README.md)

## 安装

本包声明 Dart SDK `>=3.7.0 <4.0.0`。运行完整 workspace 时还需满足 SQLite
依赖的 Dart 3.10 要求。

```yaml
dependencies:
  laconic: ^6.0.0
  laconic_mysql: ^5.0.0
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
    // useSsl: true, // 可选，默认 true
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
| `useSsl` | `bool` | `true` | 是否与服务端协商 TLS |
| `allowBadCertificates` | `bool` | `false` | 是否接受无效 TLS 证书；仅用于开发环境 |
| `securityContext` | `SecurityContext?` | `null` | TLS 自定义信任证书配置 |
| `allowPublicKeyRetrieval` | `bool` | `true` | 非 TLS `caching_sha2_password` 认证时是否请求服务端 RSA 公钥 |
| `serverPublicKey` | `String?` | `null` | PEM 格式的服务端固定 RSA 公钥 |
| `connectTimeout` | `Duration` | `10 秒` | 建立连接和认证的最长时间 |
| `commandTimeout` | `Duration` | `10 秒` | 单条数据库命令的最长执行时间 |

## 连接安全

TLS 默认开启。服务端证书由系统信任的 CA 签发时无需额外配置；使用私有 CA
时，可以创建信任该 CA 的 `SecurityContext`：

```dart
import 'dart:io';

final context = SecurityContext(withTrustedRoots: true)
  ..setTrustedCertificates('certificates/mysql-ca.pem');

final config = MysqlConfig(
  database: 'my_database',
  password: 'password',
  securityContext: context,
);
```

`allowBadCertificates: true` 会关闭证书校验，只适用于隔离的开发环境，生产环境
不要开启。

MySQL 8.4 及更高版本通常使用 `caching_sha2_password`。当
`useSsl: false` 时，Laconic 会使用服务端 RSA 公钥加密密码。为保证兼容性，
默认允许向服务端请求公钥，但在不可信网络上该过程可能遭受主动中间人攻击。
无法使用 TLS 时，应配置可信的 PEM `serverPublicKey`，并设置
`allowPublicKeyRetrieval: false`。

```dart
import 'dart:io';

final publicKey =
    await File('certificates/mysql-server-public-key.pem').readAsString();

final config = MysqlConfig(
  database: 'my_database',
  password: 'password',
  useSsl: false,
  serverPublicKey: publicKey,
  allowPublicKeyRetrieval: false,
);
```

如果是可信的本机或内网环境且不需要固定公钥，可以直接使用
`MysqlConfig(..., useSsl: false)` 自动获取服务端公钥。这样能够防止密码被被动
监听，但无法验证服务端身份，因此条件允许时仍应优先使用 TLS。

## 从 4.x 升级到 5.0

- 需要 `laconic: ^6.0.0`。
- `selectStream` 使用客户端的流式结果集；核心构建器提供 `cursor()`、`lazy()`、`lazyById()`。
- 新增 JSON contains/key/length/overlaps 及 `->` 路径、全文检索、`whereBinary`、`straightJoin`、索引提示、LATERAL JOIN、`insertOrIgnoreUsing`、`groupLimit`。
- 同一连接上的命令按顺序完成；事务内多个查询也会串行执行准备、缓存访问和命令收发。
- 同实例嵌套事务会明确报错；使用多个驱动实例时，各自保留数据库与事务归属。
- 完整发布记录见 [CHANGELOG](CHANGELOG.md)。

## 从 2.x 迁移

- TLS 现在默认开启。只有可信的 MySQL 服务端不支持 TLS 时，才添加
  `useSsl: false`。
- 客户端专用的 `MySQL*Exception` 类不再是公共 API；驱动操作应捕获
  `LaconicException`。
- 不要导入 `package:laconic_mysql/src/client/...`；内嵌客户端属于内部实现。

## 连接池

驱动内部维护轻量连接池：

- 首次查询时惰性创建连接
- 非事务查询借用连接后**始终**归还（**包括 SQL 抛错时**）
- 事务通过 Zone 在回调期间固定同一连接
- 应用退出时调用 `close()` 关闭连接池

这样可避免连续查询失败导致连接槽位耗尽、后续请求永久等待。

## 结果处理与性能

参数化查询使用二进制协议和每连接最多 50 条语句的预编译缓存；无参数查询使用文本协议。
分片接收按包头分配缓冲区并增量写入，大字段或 TLS 分片不会反复复制全部已接收数据。
结果直接转换为类型化值列表并共享列元数据，保留重复列名和可修改结果的行为。

## UPDATE 返回值

MySQL 更新采用“匹配行数”语义。只要 `WHERE` 条件匹配到一行，即使提交的值
与数据库现有值完全相同，也返回 `1`；原记录不存在时返回 `0`。调用方因此可以
区分“记录存在但数据未变化”和“记录已被并发删除”。

本包在内部维护 MySQL 客户端实现，应用无需额外依赖或覆盖 `mysql_client`。

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

## 许可证

MIT License
