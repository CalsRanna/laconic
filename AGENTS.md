# AGENTS.md

本文档为 AI 编程助手在本仓库中编写代码时提供指导。

## 项目概览

Laconic 是一个 Laravel 风格的 Dart SQL 查询构造器，支持 MySQL、SQLite 和 PostgreSQL。它提供流畅、可链式调用的 API，用于构建和执行参数化数据库查询，拥有 57+ 个方法，覆盖了 Laravel Query Builder 约 75% 的核心功能。

该项目是一个 **Dart workspace 单体仓库**（SDK >=3.7.0），包含四个包：

| 包 | 用途 | 关键依赖 |
|---------|---------|---------------|
| `packages/laconic/` | 核心查询构造器、抽象 `SqlGrammar`、`DatabaseDriver` 接口、共享类型 | *(无)* |
| `packages/laconic_sqlite/` | SQLite 驱动 + 语法 | `sqlite3: ^3.3.2` |
| `packages/laconic_mysql/` | MySQL 驱动 + 语法 | `mysql_client: ^0.0.27` |
| `packages/laconic_postgresql/` | PostgreSQL 驱动 + 语法 | `postgres: ^3.5.4` |

workspace 根目录的 `pubspec.yaml` 定义了 workspace 成员；各个包使用 `resolution: workspace` 并依赖 `laconic: ^2.2.0`。

## 常用命令

所有命令从 workspace 根目录（`D:\Code\laconic`）执行。

### 测试
```bash
# 运行所有包的全部测试
dart test

# 运行单个包的测试
cd packages/laconic_sqlite && dart test
cd packages/laconic_mysql && dart test
cd packages/laconic_postgresql && dart test

# 按名称模式运行特定测试
dart test --name "test_name"

# 核心包测试（无需 Docker，使用 MockDriver）
cd packages/laconic && dart test

# MySQL 和 PostgreSQL 测试需要 Docker 容器
docker-compose up -d
cd packages/laconic_mysql && dart test
cd packages/laconic_postgresql && dart test
docker-compose down
```

### 代码质量
```bash
# 所有包的静态分析
dart analyze

# 自动修复 lint 问题
dart fix --apply
```

### 依赖管理
```bash
dart pub get        # 安装 workspace 范围内依赖
dart pub upgrade    # 更新依赖
```

### 运行示例
```bash
dart run packages/laconic/example/laconic_example.dart
```

## 架构

### 分层设计

```
用户代码
    │
    ▼
Laconic 类 ───────── 入口点：table() → QueryBuilder、transaction()、close()、查询监听器
    │
    ▼
QueryBuilder ────────── 流式 API：将子句收集到列表结构中（_wheres、_joins、_orders 等）
    │  ▲
    │  └── JoinClause ── JOIN ON 条件的构造器（24 个方法）
    │
    ▼
SqlGrammar（抽象类） ─ 将子句列表编译为 CompiledQuery{sql, bindings}
    │
    ├── SqliteGrammar      （? 占位符）
    ├── MysqlGrammar       （? 占位符）
    └── PostgresqlGrammar  （$1, $2, ... 占位符 + RETURNING 子句）
    │
    ▼
DatabaseDriver（接口） ── 对真实数据库执行 SQL
    │
    ├── SqliteDriver       （sqlite3 原生，延迟初始化数据库连接）
    ├── MysqlDriver        （mysql_client 连接池，runZoned 事务）
    └── PostgresqlDriver   （postgres 连接池，runZoned 事务）
```

### 查询执行流程

1. `laconic.table('users').where('active', true).get()`
2. `table()` 创建一个 `QueryBuilder`，持有对 `Laconic` 实例和驱动语法的引用
3. `.where('active', true)` 将 `{type: 'basic', column: 'active', comparator: '=', value: true, boolean: 'and'}` 追加到 `_wheres` 列表
4. `.get()` 调用 `_grammar.compileSelect(...)` 并传入所有累积的子句列表
5. 语法层构建 SQL 字符串 + 绑定列表，返回 `CompiledQuery{sql, bindings}`
6. `_laconic.select(compiled.sql, compiled.bindings)` 触发查询监听器（如果设置了的话），然后委托给驱动
7. 驱动使用参数化绑定执行 SQL，返回 `List<LaconicResult>`

### 参数绑定策略

| 数据库 | 占位符 | 语法层 |
|----------|-------------|---------|
| SQLite | `?` | `SqliteGrammar` — 所有编译方法均输出 `?` |
| MySQL | `?` | `MysqlGrammar` — 与 SQLite 语法几乎相同 |
| PostgreSQL | `$1, $2, ...` | `PostgresqlGrammar` — 每个参数使用 `$${bindings.length + 1}` |

PostgreSQL 驱动还有一个安全网 `_convertPlaceholders()`，可以将原始 SQL 中的 `?` 转换为 `$N`，但如果 SQL 已包含 `$N` 模式则会短路跳过。

### 连接和事务管理

- **SQLite**：延迟初始化 `sqlite3.Database`，单连接。事务使用原始 `BEGIN/COMMIT/ROLLBACK` SQL。
- **MySQL**：延迟初始化 `MySQLConnectionPool`（最大 10 个连接）。事务使用 `connectionPool.transactional()` + `runZoned`，通过 `_txConnKey` 区域值将事务中的所有查询固定到同一连接。有参数时使用预编译语句（二进制协议）；无参数查询（DDL 兼容）使用文本协议。
- **PostgreSQL**：延迟初始化 `postgres.Pool`（最大 10 个连接）。事务使用 `pool.withConnection()` + `conn.runTx()` + `runZoned`，通过 `_txSessionKey` 区域值固定会话。始终使用扩展查询协议（`Session.prepare()`）。
- 所有驱动：连接保持打开状态，直到显式调用 `close()`。语法实例是每个驱动的 `static final` 单例。

## 核心文件图谱

```
packages/laconic/lib/
├── laconic.dart                    # Barrel 文件：导出所有公共 API
└── src/
    ├── laconic.dart                # Laconic 类（入口点，委托给驱动）
    ├── database_driver.dart        # DatabaseDriver 抽象接口（5 个方法 + grammar getter）
    ├── exception.dart              # LaconicException（message、cause、stackTrace）
    ├── expression.dart             # Expression 类 + 顶层 raw() 函数（原始 SQL 嵌入）
    ├── query.dart                  # LaconicQuery（SQL + 绑定，用于日志记录；rawSql 已 @Deprecated）
    ├── result.dart                 # LaconicResult（columns + values，[] 访问器，toMap()）
    ├── grammar/
    │   ├── grammar.dart            # SqlGrammar 抽象类（8 个 compile 方法）
    │   └── compiled_query.dart     # CompiledQuery {sql, bindings}
    └── query_builder/
        ├── query_builder.dart      # QueryBuilder（约 1440 行，57+ 个可链式调用的方法）
        └── join_clause.dart        # JoinClause（约 495 行，24 个 JOIN ON 条件方法）

packages/laconic_sqlite/lib/src/
├── sqlite_config.dart              # SqliteConfig {path}
├── sqlite_driver.dart              # SqliteDriver（延迟初始化 sqlite3.Database，单例语法）
├── sqlite_grammar.dart             # SqliteGrammar（? 占位符）
└── laconic_sqlite.dart             # Barrel 文件

packages/laconic_mysql/lib/src/
├── mysql_config.dart               # MysqlConfig {host, port, database, username, password}
├── mysql_driver.dart               # MysqlDriver（延迟初始化 MySQLConnectionPool，runZoned 事务隔离）
├── mysql_grammar.dart              # MysqlGrammar（? 占位符，与 SQLite 几乎相同）
└── laconic_mysql.dart              # Barrel 文件

packages/laconic_postgresql/lib/src/
├── postgresql_config.dart          # PostgresqlConfig {host, port, database, username, password, useSsl}
├── postgresql_driver.dart          # PostgresqlDriver（延迟初始化 postgres Pool，runZoned 事务隔离）
├── postgresql_grammar.dart         # PostgresqlGrammar（$N 占位符，RETURNING 子句）
└── laconic_postgresql.dart         # Barrel 文件
```

## 关键设计模式

### 语法模式（策略模式）
QueryBuilder 将查询组件收集到列表数据结构中（`_wheres`、`_joins`、`_orders`、`_groups`、`_havings`）。SQL 生成完全委托给 `SqlGrammar` 子类。这将查询构造器 API 与数据库特定的 SQL 语法解耦。

### 参数绑定防止 SQL 注入
所有用户值都经过参数化绑定。语法层在编译过程中将绑定收集到有序列表中。WHERE 类型 `column`、`betweenColumns` 和 `null` 不需要绑定（列比较 / 字面量 NULL）。`Expression` 类（`raw()`）允许在不进行参数化的情况下嵌入原始 SQL——请谨慎使用。

### 每个驱动单例语法
每个驱动持有一个 `static final` 语法实例，避免每次查询都重新分配。语法层是无状态的——它们仅在每次 compile 调用期间读取输入参数并写入本地 `bindings` 列表。

### runZoned 事务隔离
MySQL 和 PostgreSQL 驱动使用 Dart 的 `runZoned` 配合区域值，通过调用栈传播固定的事务连接/会话。`_executeQuery` 检查 `Zone.current[_txConnKey]`（MySQL）或 `Zone.current[_txSessionKey]`（PostgreSQL），以路由到事务连接而非连接池。

### 延迟连接初始化
所有驱动通过 getter 模式（`_pool ??= ...`）将连接/连接池的创建推迟到首次查询。

## WHERE 子句类型系统

存储在 `_wheres` 中的每个 WHERE 条件都是一个 `Map<String, dynamic>`，其中 `type` 字段驱动语法编译：

| `type` | 公共方法 | 是否有绑定 | 说明 |
|--------|---------------|-------------|-------|
| `basic` | `where()`、`orWhere()` | 是 | 最常用。支持 `raw()` Expression 值。 |
| `column` | `whereColumn()`、`orWhereColumn()` | 否 | 列对列比较 |
| `in` | `whereIn()`、`orWhereIn()`、`whereNotIn()`、`orWhereNotIn()` | 是 | 空列表 → `1=0`（IN）或 `1=1`（NOT IN） |
| `null` | `whereNull()`、`orWhereNull()`、`whereNotNull()`、`orWhereNotNull()` | 否 | IS NULL / IS NOT NULL |
| `between` | `whereBetween()`、`orWhereBetween()`、`whereNotBetween()`、`orWhereNotBetween()` | 是 | 2 个绑定 |
| `betweenColumns` | `whereBetweenColumns()`、`orWhereBetweenColumns()`、`orWhereNotBetweenColumns()` 等 | 否 | BETWEEN col1 AND col2 |
| `all` | `whereAll()`、`orWhereAll()` | 是 | `(col1 = ? AND col2 = ? AND ...)` — 每列 1 个绑定 |
| `any` | `whereAny()`、`orWhereAny()` | 是 | `(col1 = ? OR col2 = ? OR ...)` — 每列 1 个绑定 |
| `none` | `whereNone()` | 是 | `NOT (col1 = ? OR col2 = ? OR ...)` — 每列 1 个绑定 |
| `raw` | `whereRaw()`、`orWhereRaw()` | 是 | 带绑定的原始 SQL 字符串 |
| `nested` | *(内部使用)* | 不适用 | 递归 `_wheres` 列表——支持子分组 |

每个条件都有一个 `boolean` 字段（`'and'` 或 `'or'`）。第一个条件省略布尔关键字。

## JOIN 系统

`_joins` 列表中存储四种 JOIN 类型，带 `type` 字段：`inner`、`left`、`right`、`cross`。

`JoinClause` 是一个独立的构造器类，拥有自己的条件列表。Join 条件类型：`on`、`where`、`column`、`null`、`in`、`between`、`betweenColumns`、`raw`。与 WHERE 的关键区别：`on` 比较两列（无绑定），`where` 比较列与值（有绑定）。JoinClause 条件始终出现在 `ON (...)` 子句中。

## 约定

### 添加新的 WHERE 类型
1. 在 `QueryBuilder`（`packages/laconic/lib/src/query_builder/query_builder.dart`）中添加公共方法
   - 向 `_wheres` 追加一个 map，包含新的 `type` 字符串、`boolean` 和类型特定的键
2. 在 **所有** 语法层的 `_compileWheres()` 方法中添加编译逻辑：
   - `packages/laconic_sqlite/lib/src/sqlite_grammar.dart` 中的 `SqliteGrammar`
   - `packages/laconic_mysql/lib/src/mysql_grammar.dart` 中的 `MysqlGrammar`
   - `packages/laconic_postgresql/lib/src/postgresql_grammar.dart` 中的 `PostgresqlGrammar`
3. 如果类型有 OR 变体，按照已有的 `or*` 模式添加
4. 如果 `increment()`/`decrement()` 应支持该类型，更新它们的 WHERE 编译
5. 在所有三个数据库测试文件中添加测试

### 添加新的数据库驱动
1. 创建 `packages/laconic_newdb/`，其中 `pubspec.yaml` 依赖 `laconic: ^2.2.0`
2. 创建一个继承 `SqlGrammar` 的 `Grammar` 类——实现全部 8 个抽象 compile 方法
3. 创建一个实现 `DatabaseDriver` 的 `Driver` 类——实现全部 5 个方法 + `grammar` getter
4. 使用 `static final` 语法实例单例
5. 创建一个 `Config` 类用于连接参数
6. 添加到 workspace 根目录 `pubspec.yaml` 的 workspace 列表中
7. 按照已有模式创建测试文件，包含 `test_helper.dart`

### 错误处理
- 所有驱动方法 **必须** 用 try/catch 包裹方法体，并以 `LaconicException(message, cause: e, stackTrace: stackTrace)` 重新抛出。这保留了原始错误以便调试。
- QueryBuilder 会尽早验证输入，对无效用法（空插入数据等）抛出 `LaconicException`
- `first()` 在无结果时抛出 `LaconicException`
- `sole()` 在无结果 **或** 多条结果时抛出 `LaconicException`（获取 2 行以检查）
- `value()` 在无结果时返回 `null`（**不** 抛出异常）
- `delete()`、`increment()`、`decrement()` 在 `_wheres` 为空时抛出 `LaconicException`，除非传入 `allowWithoutWhere: true`
- 事务回滚失败会被捕获并与原始错误一起报告

### 公共 API 接口
核心包从 `lib/laconic.dart` 导出：
- `Laconic` 类、`DatabaseDriver`（抽象）、`SqlGrammar`（抽象）、`CompiledQuery`
- `QueryBuilder`、`JoinClause`、`LaconicResult`、`LaconicQuery`、`LaconicException`
- `Expression` 类 + `raw()` 顶层函数

## 测试策略

### 测试文件布局
- `packages/laconic/test/laconic_test.dart` — 使用 `MockGrammar` + `MockDriver` 的核心测试（无真实数据库，约 15 个测试）
- `packages/laconic_sqlite/test/laconic_sqlite_test.dart` — SQLite 集成测试（约 70 个测试）
- `packages/laconic_mysql/test/laconic_mysql_test.dart` — MySQL 集成测试（需要 Docker）
- `packages/laconic_postgresql/test/laconic_postgresql_test.dart` — PostgreSQL 集成测试（需要 Docker）

### 测试辅助文件
每个数据库包都有一个 `test/test_helper.dart`，包含：
- 共享的表名常量（`userTable`、`postTable`、`commentTable`）
- 共享的测试数据（`testUsers`、`testPosts`、`testComments`）
- 数据库特定的 DDL（`SqliteSchema`、`MysqlSchema`、`PostgresqlSchema`）
- `setup*TestData(Laconic)` 函数：删除表、创建 schema、插入测试数据

### 测试覆盖类别（每个数据库测试文件）
基础 CRUD、检索方法（first、sole、get、value、pluck）、所有 WHERE 类型 + OR 变体、聚合函数（count、avg、sum、max、min）、存在性检查（exists、doesntExist）、排序（orderBy、orderByDesc、orderByRaw）、分组和 HAVING、limit/offset、distinct、select/addSelect/selectRaw、increment/decrement、安全检查（无 WHERE 的 delete/increment/decrement 会抛出异常）、JOIN 操作、事务支持、`when()` 条件方法。

### 快速迭代循环
开发过程中如需快速反馈，使用 SQLite：
```bash
cd packages/laconic_sqlite && dart test
```
仅当更改影响跨数据库行为或准备好进行完整验证时，才运行 MySQL/PostgreSQL 测试。

## 调试指南

| 症状 | 检查位置 |
|---------|-------|
| 查询生成的 SQL 不符合预期 | 相关语法层的 `_compileWheres()` 或 `_compileJoins()` |
| 参数绑定不匹配 | 语法层是否创建了正确数量的占位符，并按顺序添加到 `bindings` 列表 |
| PostgreSQL 特有的 bug | `PostgresqlGrammar` 中的 `$N` 语法 **和** 驱动中的 `_convertPlaceholders` 安全网 |
| 事务隔离失败 | MySQL/PostgreSQL 驱动中的 `runZoned` 区域值 |

## 依赖

### 核心包（`packages/laconic`）
- 零运行时依赖。开发依赖：`lints: ^5.1.1`、`test: ^1.25.15`。

### SQLite 驱动
- `sqlite3: ^3.3.2` — 通过 `dart:ffi` 使用原生 SQLite。使用 `Database.prepare()` 进行参数化语句。

### MySQL 驱动
- `mysql_client: ^0.0.27` — 纯 Dart MySQL 客户端，带连接池。

### PostgreSQL 驱动
- `postgres: ^3.5.4` — PostgreSQL 客户端，带 `Pool` 连接池。使用 `Session.prepare()`（扩展查询协议）。
