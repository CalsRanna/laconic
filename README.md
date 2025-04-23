# Laconic

一个受 Laravel 启发的 Dart SQL 查询构建器，支持 MySQL 和 SQLite，旨在提供灵活、可移植且易于使用的数据库交互方式。

## 特性 (Features)

*   **流式接口 (Fluent Interface):** 提供类似于 Laravel 查询构建器的链式调用方法。
*   **多数据库支持 (Multi-DB Support):** 目前支持 MySQL 和 SQLite。
*   **查询构建 (Query Building):**
    *   支持 `select`, `insert`, `update`, `delete` 语句。
    *   支持 `where`, `orWhere` 条件子句。
    *   支持 `orderBy` 排序。
    *   支持 `limit` 和 `offset` 分页。
    *   支持 `join` 连接。
*   **原始 SQL 执行 (Raw SQL Execution):** 允许执行原始的 SQL 查询和语句。
*   **配置简单 (Simple Configuration):** 使用专门的配置类 (`MysqlConfig`, `SqliteConfig`) 进行数据库连接设置。
*   **结果处理 (Result Handling):** 查询结果以 `LaconicResult` 对象列表返回，方便访问列数据。

## 开始使用 (Getting Started)

将此包添加到你的 `pubspec.yaml` 文件中：

```yaml
dependencies:
  laconic: ^latest # 请替换为所需的版本号
```

或者使用命令行安装：

```bash
dart pub add laconic
```

## 用法 (Usage)

### 1. 导入包 (Import the package)

```dart
import 'package:laconic/laconic.dart';
```

### 2. 连接数据库 (Connecting to the Database)

你需要先创建一个 `Laconic` 实例，并根据你的数据库类型提供相应的配置。

**MySQL:**

```dart
var mysqlConfig = MysqlConfig(
  database: 'laconic_test', // 数据库名
  host: '127.0.0.1',      // 主机地址
  password: 'password',     // 密码
  port: 3306,             // 端口
  username: 'root',         // 用户名
);
var laconic = Laconic.mysql(mysqlConfig);
```

**SQLite:**

```dart
var sqliteConfig = SqliteConfig('path/to/your/database.db'); // SQLite 文件路径
var laconic = Laconic.sqlite(sqliteConfig);
```

### 3. 执行原始 SQL 查询 (Executing Raw SQL Queries)

你可以直接执行 SQL 字符串。

**执行 SELECT 查询:**

```dart
// 查询所有用户
List<LaconicResult> allUsers = await laconic.select('select * from users');

// 带参数查询
List<LaconicResult> userById = await laconic.select('select * from users where id = ?', [1]);

// 遍历结果
for (var user in userById) {
  print('User ID: ${user['id']}, Name: ${user['name']}');
}
```

**执行 INSERT, UPDATE, DELETE 语句:**

```dart
// 插入数据
await laconic.statement(
  'insert into users (id, name, age, gender) values (?, ?, ?, ?)',
  [5, 'Alice', 30, 'female'],
);

// 更新数据
await laconic.statement('update users set name = ? where id = ?', ['Bob', 5]);

// 删除数据
await laconic.statement('delete from users where id = ?', [5]);
```

### 4. 使用查询构建器 (Using the Query Builder)

查询构建器提供了一种更结构化和安全的方式来构建 SQL 查询。

**获取多条记录 (`get`):**

```dart
List<LaconicResult> users = await laconic.table('users').get();
List<LaconicResult> activeUsers = await laconic.table('users').where('status', 'active').get();
```

**获取单条记录 (`first`):**

```dart
try {
  LaconicResult user = await laconic.table('users').where('id', 1).first();
  print('First user name: ${user['name']}');
} on LaconicException catch (e) {
  print('User not found: $e');
}
```

**查询特定列 (`select`):**

```dart
List<LaconicResult> userNames = await laconic.table('users').select(['name', 'email']).get();
```

**使用 `where` 子句:**

```dart
// 等于
List<LaconicResult> usersAge25 = await laconic.table('users').where('age', 25).get();

// 其他比较符
List<LaconicResult> usersOlderThan30 = await laconic.table('users').where('age', 30, comparator: '>').get();
```

**使用 `orWhere` 子句:**

```dart
List<LaconicResult> specificUsers = await laconic.table('users')
    .where('status', 'active')
    .orWhere('name', 'Admin')
    .get();
```

**插入记录 (`insert`):**

```dart
await laconic.table('users').insert({
  'id': 6,
  'name': 'Charlie',
  'age': 28,
  'gender': 'male',
});
```

**更新记录 (`update`):**

```dart
await laconic.table('users').where('id', 6).update({'age': 29});
```

**删除记录 (`delete`):**

```dart
await laconic.table('users').where('id', 6).delete();
```

**排序 (`orderBy`):**

```dart
// 按年龄升序
List<LaconicResult> usersByAgeAsc = await laconic.table('users').orderBy('age').get();

// 按姓名降序
List<LaconicResult> usersByNameDesc = await laconic.table('users').orderBy('name', direction: 'desc').get();
```

**限制和偏移 (`limit`, `offset`):**

```dart
// 获取前 5 条记录
List<LaconicResult> first5Users = await laconic.table('users').limit(5).get();

// 获取第 6 到第 10 条记录 (跳过前 5 条)
List<LaconicResult> usersPage2 = await laconic.table('users').offset(5).limit(5).get();
```

**连接表 (`join`):**

使用 `join` 方法可以连接其他表。你需要提供目标表名和一个回调函数来定义连接条件。

```dart
// 查询用户及其对应的帖子标题
List<LaconicResult> usersWithPosts = await laconic.table('users')
    .select(['users.name', 'posts.title'])
    .join('posts', (builder) {
      // 定义 ON 条件 users.id = posts.user_id
      builder.on('users.id', 'posts.user_id');
      // 可以链式调用 .on() 添加更多 AND 条件
      // builder.on('users.status', 'posts.status'); 
    })
    .where('users.status', 'active')
    .get();
```

#### 注意事项

- 建议使用表名限定列名避免歧义。
- 当前 `join` 默认执行 `INNER JOIN`。回调函数中的多个 `on` 条件会使用 `AND` 连接。

### 5. 事务支持 (Transaction)

Laconic 支持数据库事务，允许你将一组数据库操作作为一个原子单元执行。

如果事务中的任意操作失败，所有更改都会被自动回滚，保证数据一致性。

#### 适用场景

- 需要保证多条 SQL 语句要么全部成功、要么全部失败时（如银行转账、批量写入等）。

#### 用法

你可以通过 `laconic.transaction` 方法将需要在同一事务中执行的操作包裹起来。

```dart
await laconic.transaction(() async {
  await laconic.table('users').insert({'id': 7, 'name': 'Eve'});
  await laconic.table('accounts').where('user_id', 7).update({'balance': 100});
  // 如果这里抛出异常，以上所有更改都会自动回滚
});
```

如果 `action` 回调内所有操作都成功，事务会自动提交。

如果有任何异常抛出，事务会自动回滚。

#### 注意事项

- 支持 MySQL 和 SQLite 两种数据库，底层会自动选择合适的事务语法。
- 事务回调 (`action`) 可以是异步操作。


### 6. 关闭连接 (Closing the Connection)

当你的应用不再需要数据库连接时，应该关闭它以释放资源。

```dart
await laconic.close();
```

## 查询监听 （Query Listener）

Laconic 支持通过 listen 回调监听所有即将执行的 SQL 语句及其参数。这对于调试、日志记录、SQL 审计等场景非常有用。

### 用法示例

```dart
var laconic = Laconic.sqlite(
  SqliteConfig('path/to/your/database.db'),
  listen: (query) {
    // 你可以在这里记录日志、做SQL分析等
  },
);
```

每当你调用 select、statement 等方法时，listen 回调都会被触发，参数为 LaconicQuery 对象，包含绑定参数、 SQL 字符串和执行时间戳。

### 典型应用场景

* 调试：实时输出所有执行的 SQL，方便排查问题。
* 日志记录：将 SQL 及参数写入日志文件，便于后期审计。
* 安全审查：对即将执行的 SQL 进行分析和过滤，防止危险操作。

## 附加信息 (Additional Information)

*   这个库目前仍处于开发阶段 (WIP)。API 在未来可能会发生不兼容的更改。如果你决定在生产环境中使用，请自行承担风险。
*   请参考 `example/` 目录获取更多使用示例。
*   欢迎提出 Issue 和 Pull Request！
