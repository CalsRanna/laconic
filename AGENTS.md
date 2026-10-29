# AGENTS.md

本文档为 AI 编程助手在本仓库中编写代码时提供指导。

## 项目概览

Laconic 是一个 Laravel 风格的 Dart SQL 查询构造器，支持 MySQL、MariaDB、SQLite、PostgreSQL 和 SQL Server。它提供流畅、可链式调用的 API，用于构建和执行参数化数据库查询，拥有 130+ 个公开方法，覆盖查询、子查询、分页、流式读取、JSON/全文检索和方言特性。

该项目是一个 **Dart workspace 单体仓库**（SDK >=3.7.0），包含六个包：

| 包 | 用途 | 关键依赖 |
|---------|---------|---------------|
| `packages/laconic/` | 核心查询构造器、抽象 `SqlGrammar`、`DatabaseDriver` 接口、共享类型 | *(无)* |
| `packages/laconic_sqlite/` | SQLite 驱动 + 语法 | `sqlite3: ^3.3.2` |
| `packages/laconic_mysql/` | MySQL 驱动 + 内嵌客户端 + 语法 | `buffer: ^1.1.1`、`crypto: ^3.0.1` |
| `packages/laconic_postgresql/` | PostgreSQL 驱动 + 语法 | `postgres: ^3.5.4` |

新增驱动：`packages/laconic_mariadb/`（MariaDB 10.11+，复用 `laconic_mysql`）和
`packages/laconic_sqlserver/`（SQL Server 2022+，依赖 `mssql: ^0.2.0`），首版均为
`1.0.0`（尚未发布）。完整测试还需包含这两个包的 `test` 目录。
MariaDB 不支持 LATERAL；SQL Server 使用 TOP/OFFSET、OUTPUT、MERGE、APPLY 和表锁提示，
不支持的接口会抛出异常；完整能力边界见各包 README。
核心 `SqlGrammar.compileAggregateExpression` 允许 SQL Server 为 AVG 输入添加类型转换。

workspace 根目录的 `pubspec.yaml` 定义了 workspace 成员；各个包使用 `resolution: workspace` 并依赖 `laconic: ^6.0.0`（当前发布线：核心 6.0、SQLite/PostgreSQL 4.0、MySQL 5.0）。

## 常用命令

所有命令从 workspace 根目录执行。

### 测试
```bash
# 运行所有包的全部测试（推荐显式列出）
dart test packages/laconic/test packages/laconic_sqlite/test \
  packages/laconic_mysql/test packages/laconic_postgresql/test --concurrency=1

# 运行单个包的测试
cd packages/laconic_sqlite && dart test
cd packages/laconic_mysql && dart test
cd packages/laconic_postgresql && dart test

# 按名称模式运行特定测试
cd packages/laconic_sqlite && dart test --name "test_name"

# 核心包测试（无需 Docker，使用 MockDriver）
cd packages/laconic && dart test

# MySQL 和 PostgreSQL 测试需要 Docker 容器
docker compose up -d --wait
cd packages/laconic_mysql && dart test
cd packages/laconic_postgresql && dart test
docker compose down
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
Laconic 类 ───────── 入口点：table() → QueryBuilder、transaction()、close()、
    │                 listen / beforeQuery / afterQuery、select() / selectStream()
    ▼
QueryBuilder ────────── 流式 API：将子句收集到列表结构中（_wheres、_joins、_orders 等）
    │  ▲                分页、cursor/lazy、子查询、groupLimit、JSON/全文
    │  └── JoinClause ── JOIN ON 条件的构造器（含 raw/nested 条件）
    │
    ▼
SqlGrammar（抽象类） ─ 将子句列表编译为 CompiledQuery{sql, bindings}
    │
    ├── SqliteGrammar      （? 占位符，FTS5、JSON1）
    ├── MysqlGrammar       （? 占位符，JSON、全文、binary、索引提示）
    └── PostgresqlGrammar  （$1, $2, ... 占位符 + RETURNING、JSONB、updateFrom）
    │
    ▼
DatabaseDriver（接口） ── 对真实数据库执行 SQL
    │
    ├── SqliteDriver       （sqlite3 原生，单连接，原生游标 selectStream）
    ├── MysqlDriver        （内嵌 MySQL 客户端连接池，流式结果集，runZoned 事务）
    └── PostgresqlDriver   （postgres 连接池，ResultStream，runZoned 事务）
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

PostgreSQL 使用 `PostgresqlPlaceholders` 做单次扫描的占位符转换，并在嵌入子查询时按当前绑定偏移重编号 `$N`；`inlineSubquery()` 会把子查询归一化为 `?`，交给外层 SELECT 编译器统一编号。`??` 可用于在原始片段中转义问号运算符。

### 连接和事务管理

- **SQLite**：延迟初始化 `sqlite3.Database`，单连接。事务使用原始 `BEGIN/COMMIT/ROLLBACK` SQL。
- **MySQL**：延迟初始化 `MysqlConnectionPool`（默认最大 10 个连接）。事务使用 `connectionPool.transactional()` + `runZoned`，通过 `_txConnKey` 区域值将事务中的所有查询固定到同一连接。有参数时使用预编译语句（二进制协议）；无参数查询（DDL 兼容）使用文本协议。内嵌 client 将连接 facade、命令执行、握手、transport、结果模型和协议编解码分层。
- **PostgreSQL**：延迟初始化 `postgres.Pool`（最大 10 个连接）。事务使用 `pool.withConnection()` + `conn.runTx()` + `runZoned`，通过 `_txSessionKey` 区域值固定会话。始终使用扩展查询协议（`Session.prepare()`）。
- 所有驱动：连接保持打开状态，直到显式调用 `close()`。语法实例是每个驱动的 `static final` 单例。
- 流式读取：SQLite 的 `selectStream()` 在消费期间独占单连接；MySQL/PostgreSQL 的 `selectStream()` 在流完成或取消前持有一个池连接。

## 核心文件图谱

```
packages/laconic/lib/
├── laconic.dart                    # Barrel 文件：导出所有公共 API
└── src/
    ├── laconic.dart                # Laconic 类（入口点、selectStream、beforeQuery/afterQuery）
    ├── database_driver.dart        # DatabaseDriver 抽象接口（select/selectStream/statement/...）
    ├── exception.dart              # LaconicException（message + driver + code）
    ├── expression.dart             # Expression 类 + 顶层 raw() 函数（原始 SQL 嵌入）
    ├── operator.dart               # 比较运算符白名单校验
    ├── pagination.dart             # LaconicPage / LaconicSimplePage / LaconicCursorPage
    ├── query.dart                  # LaconicQuery（SQL + 绑定，用于日志记录）
    ├── result.dart                 # LaconicResult（columns + values，[] 访问器，toMap()）
    ├── grammar/
    │   ├── grammar.dart            # SqlGrammar 抽象类（SELECT/UNION/写入/子查询能力）
    │   └── compiled_query.dart     # CompiledQuery {sql, bindings}
    └── query_builder/
        ├── query_builder.dart      # QueryBuilder（约 3800 行，130+ 个可链式调用的方法）
        └── join_clause.dart        # JoinClause（约 620 行，ON/WHERE/raw/nested 条件）

packages/laconic_sqlite/lib/src/
├── sqlite_config.dart              # SqliteConfig {path}
├── sqlite_driver.dart              # SqliteDriver（延迟初始化 sqlite3.Database，原生 selectStream）
├── sqlite_grammar.dart             # SqliteGrammar（? 占位符，JSON1、FTS5）
└── laconic_sqlite.dart             # Barrel 文件

packages/laconic_mysql/lib/src/
├── mysql_config.dart               # MysqlConfig {host, port, database, username, password}
├── mysql_driver.dart               # MysqlDriver（连接池、流式结果集、runZoned 事务隔离）
├── mysql_grammar.dart              # MysqlGrammar（? 占位符，JSON/全文/binary/索引提示）
└── client/
    ├── connection/                 # connection、pool、handshake、command executor
    ├── transport/                  # Socket 分帧、重组、sequence、背压
    ├── result/                     # result set（含 streaming result set）、row、prepared statement
    ├── protocol/                   # packet frame/decoder、类型和协议 payload
    └── exceptions.dart             # 内部 client 异常

packages/laconic_postgresql/lib/src/
├── postgresql_config.dart          # PostgresqlConfig {host, port, database, username, password, useSsl}
├── postgresql_driver.dart          # PostgresqlDriver（postgres Pool、ResultStream、runZoned 事务）
├── postgresql_grammar.dart         # PostgresqlGrammar（$N 占位符，JSONB、全文、updateFrom）
├── postgresql_placeholders.dart    # $N/`?` 扫描、重编号与子查询归一化
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

### 子查询嵌入
`selectSub` / `fromSub` / `fromRaw` / `joinSub` / `whereIn(subquery)` / `where` 子查询值 / `insertUsing` 都通过 `_compileSubquery()` 得到 `CompiledQuery`。SELECT 子查询在 PostgreSQL 上由 `inlineSubquery()` 归一化为 `?`，再由外层 SELECT 统一编号；FROM/JOIN/WHERE 子查询由各语法层按当前 `bindings.length` 偏移重编号。JOIN 子查询通过 `tableBindings` 传递。

### 分页与流式
分页结果类型位于 `src/pagination.dart`。`paginate` 执行 count + data 两条查询；`simplePaginate` / `cursorPaginate` 只取 `perPage + 1` 行判断是否有下一页。`cursor()` 依赖驱动的 `selectStream()`；`lazy()` 使用 offset 分块，`lazyById()` 使用 keyset 游标。SQLite 流式读取期间独占单连接，MySQL/PostgreSQL 流式读取期间持有一个池连接。

## WHERE 子句类型系统

存储在 `_wheres` 中的每个 WHERE 条件都是一个 `Map<String, dynamic>`，其中 `type` 字段驱动语法编译：

| `type` | 公共方法 | 是否有绑定 | 说明 |
|--------|---------------|-------------|-------|
| `basic` | `where()`、`orWhere()` | 是 | 最常用。支持 `raw()` Expression 值；值为 `null` 时转 IS NULL。 |
| `like` | `whereLike(caseSensitive: false)` 等 | 是 | 大小写不敏感 LIKE |
| `column` | `whereColumn()`、`orWhereColumn()` | 否 | 列对列比较 |
| `in` | `whereIn()`、`orWhereIn()`、`whereNotIn()`、`orWhereNotIn()` | 是 | List 形式；空列表 → `1=0` / `1=1` |
| `inSubquery` | 同上，传入回调或 QueryBuilder | 是 | `IN (subquery)`，按方言重编号 |
| `integerInRaw` | `whereIntegerInRaw()` 等 | 否 | 整数直接内联，空列表 → `1=0` / `1=1` |
| `rowValues` | `whereRowValues()`、`orWhereRowValues()` | 是 | `(a, b) operator (?, ?)` |
| `valueBetween` | `whereValueBetween()` 等 | 是 | `? BETWEEN col1 AND col2` |
| `nullSafeEquals` | `whereNullSafeEquals()` 等 | 是 | SQLite `IS` / MySQL `<=>` / PG `IS NOT DISTINCT FROM` |
| `binary` | `whereBinary()` 等 | 是 | 仅 MySQL，区分大小写 |
| `null` | `whereNull()`、`orWhereNull()`、`whereNotNull()`、`orWhereNotNull()` | 否 | IS NULL / IS NOT NULL |
| `between` | `whereBetween()`、`orWhereBetween()`、`whereNotBetween()`、`orWhereNotBetween()` | 是 | 2 个绑定 |
| `betweenColumns` | `whereBetweenColumns()`、`whereNotBetweenColumns()` 等 | 否 | BETWEEN col1 AND col2 |
| `all` | `whereAll()`、`orWhereAll()` | 是 | `(col1 = ? AND col2 = ? AND ...)` |
| `any` | `whereAny()`、`orWhereAny()` | 是 | `(col1 = ? OR col2 = ? OR ...)` |
| `none` | `whereNone()`、`orWhereNone()` | 是 | `NOT (col1 = ? OR ...)` |
| `subquery` | `where()` / `orWhere()` 的值为子查询 | 是 | `col operator (subquery)` |
| `jsonContains` | `whereJsonContains()` 等 | 是 | 支持 `column->path` |
| `jsonContainsKey` | `whereJsonContainsKey()` 等 | 是 | 需要路径 |
| `jsonLength` | `whereJsonLength()` 等 | 是 | 数组长度 |
| `jsonOverlaps` | `whereJsonOverlaps()` 等 | 是 | 数组/键重叠 |
| `fullText` | `whereFullText()`、`orWhereFullText()` | 是 | MySQL/PG/SQLite FTS5 |
| `date` | `whereDate/Time/Day/Month/Year` | 是 | 日期部分 + 比较符 |
| `raw` | `whereRaw()`、`orWhereRaw()` | 是 | 带绑定的原始 SQL 字符串 |
| `nested` | `whereNested()`、`whereNot(callback)` 等 | 不适用 | 递归 `_wheres` 列表，支持 `not` |

每个条件都有一个 `boolean` 字段（`'and'` 或 `'or'`）。第一个条件省略布尔关键字。

## JOIN 系统

`_joins` 列表中存储的 JOIN 类型包括 `inner`、`left`、`right`、`cross`、`straight`（MySQL）和 `lateral`（带 `joinType`）。子查询 JOIN 使用 `tableBindings` 携带绑定，PostgreSQL 按当前偏移重编号。

`JoinClause` 是一个独立的构造器类，拥有自己的条件列表。Join 条件类型：`on`、`where`、`column`、`null`、`in`、`between`、`betweenColumns`、`raw`、`exists`、`nested`。与 WHERE 的关键区别：`on` 比较两列（无绑定），`where` 比较列与值（有绑定）。JoinClause 条件始终出现在 `ON (...)` 子句中。

## 约定

### 添加新的 WHERE 类型
1. 在 `QueryBuilder`（`packages/laconic/lib/src/query_builder/query_builder.dart`）中添加公共方法
   - 向 `_wheres` 追加一个 map，包含新的 `type` 字符串、`boolean` 和类型特定的键
   - 值含子查询时使用 `_compileSubquery()`，需要路径时使用 `_splitJsonColumn()` / `_normalizeJsonPath()`
2. 在 **所有** 语法层的 `_compileWheres()` 方法中添加编译逻辑：
   - `packages/laconic_sqlite/lib/src/sqlite_grammar.dart` 中的 `SqliteGrammar`
   - `packages/laconic_mysql/lib/src/mysql_grammar.dart` 中的 `MysqlGrammar`
   - `packages/laconic_postgresql/lib/src/postgresql_grammar.dart` 中的 `PostgresqlGrammar`
   - PostgreSQL 的 `$N` 必须按当前 `bindings.length` 生成；子查询使用偏移重编号
3. 如果类型有 OR 变体，按照已有的 `or*` 模式添加
4. 如果 `increment()`/`decrement()` 应支持该类型，更新它们的 WHERE 编译
5. 方言不支持时抛出清晰的 `LaconicException`，不要静默按其他语义执行
6. 跨方言行为加入 `packages/laconic/test/query_regressions.dart`；单方言行为加入对应驱动测试文件

### 添加新的数据库驱动
1. 创建 `packages/laconic_newdb/`，其中 `pubspec.yaml` 依赖 `laconic: ^6.0.0`
2. 创建一个继承 `SqlGrammar` 的 `Grammar` 类——实现全部抽象 compile 方法，并让 `compileSelect` 接受新增的可选参数
3. 创建一个实现 `DatabaseDriver` 的 `Driver` 类——实现 `grammar`、`select`、`selectStream`、`statement`、`affectingStatement`、`insertAndGetId`、`transaction`、`close`
4. 使用 `static final` 语法实例单例
5. 创建一个 `Config` 类用于连接参数
6. 添加到 workspace 根目录 `pubspec.yaml` 的 workspace 列表中
7. 按照已有模式创建测试文件，包含 `test_helper.dart` 和 `query_regression_test.dart`

### 错误处理
- 所有驱动方法 **必须** 用 try/catch 包裹方法体，并以 `LaconicException(e.toString())` 重新抛出（若 `e` 已是 `LaconicException` 则直接 `rethrow`，避免嵌套包装导致信息重复）。
- QueryBuilder 会尽早验证输入，对无效用法（空插入数据等）抛出 `LaconicException`
- `first()`、`find()`、`firstWhere()` 在无结果时抛出 `LaconicException`；`firstOrNull()`、`findOrNull()`、`firstWhereOrNull()` 返回 `null`；`firstOr()` / `findOr()` 使用回退回调
- `sole()` 在无结果 **或** 多条结果时抛出 `LaconicException`（获取 2 行以检查）
- `value()` 在无结果时返回 `null`（**不** 抛出异常）
- `insert()` 返回 `bool`
- `delete()`、`increment()`、`decrement()`、`incrementEach()`、`decrementEach()` 在 `_wheres` 为空时抛出 `LaconicException`，除非传入 `allowWithoutWhere: true`
- 事务回滚失败会被捕获并与原始错误一起报告
- 方言不支持的操作（如 SQLite 的 binary/lateral、非 MySQL 的 `whereBinary`）在编译期抛出清晰的 `LaconicException`

### 公共 API 接口
核心包从 `lib/laconic.dart` 导出：
- `Laconic` 类、`DatabaseDriver`（抽象）、`SqlGrammar`（抽象）、`CompiledQuery`
- `QueryBuilder`、`JoinClause`、`LaconicResult`、`LaconicQuery`、`LaconicException`
- `Expression` 类 + `raw()` 顶层函数
- `LaconicPage`、`LaconicSimplePage`、`LaconicCursorPage`
- `operator.dart` 的运算符校验为内部实现，不导出

## 测试策略

### 测试文件布局
- `packages/laconic/test/laconic_test.dart` — 使用 `MockGrammar` + `MockDriver` 的核心测试（无真实数据库，约 28 个测试）
- `packages/laconic/test/query_regressions.dart` — 三个真实驱动共享的跨方言行为测试
- `packages/laconic_sqlite/test/laconic_sqlite_test.dart` — SQLite 集成测试（约 156 个测试）
- `packages/laconic_mysql/test/laconic_mysql_test.dart` — MySQL 集成测试（约 190 个测试，需要 Docker）
- `packages/laconic_postgresql/test/laconic_postgresql_test.dart` — PostgreSQL 集成测试（约 151 个测试，需要 Docker）
- 每个驱动包的 `query_regression_test.dart` 调用共享的 `query_regressions.dart`

### 测试辅助文件
每个数据库包都有一个 `test/test_helper.dart`，包含：
- 共享的表名常量（`userTable`、`postTable`、`commentTable`）
- 共享的测试数据（`testUsers`、`testPosts`、`testComments`）
- 数据库特定的 DDL（`SqliteSchema`、`MysqlSchema`、`PostgresqlSchema`）
- `setup*TestData(Laconic)` 函数：删除表、创建 schema、插入测试数据

### 测试覆盖类别
基础 CRUD、检索方法（first、sole、get、value、pluck、firstOrNull）、所有 WHERE/HAVING 类型 + OR 变体、聚合函数（count、avg、sum、max、min）、存在性检查、排序、分组、limit/offset、distinct、select/addSelect/selectRaw、increment/decrement/incrementEach、安全检查、JOIN/子查询 JOIN/LATERAL、子查询嵌入、事务、分页、cursor/lazy/lazyById、JSON、全文检索、方言特性（binary、索引提示、updateFrom、groupLimit 等）。跨方言用例优先放在 `query_regressions.dart`，仅单方言用例放在对应驱动测试文件。

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
| PostgreSQL 特有的 bug | `PostgresqlGrammar` 的 `$N` 语法、`PostgresqlPlaceholders` 的扫描/重编号，以及 `inlineSubquery()` |
| 子查询绑定错位 | SELECT 子查询的 `selectBindings`、FROM/JOIN 子查询的偏移重编号，以及 `tableBindings` |
| 事务隔离失败 | MySQL/PostgreSQL 驱动中的 `runZoned` 区域值 |
| 流式读取挂起/连接泄漏 | 驱动的 `selectStream()` 是否在完成或取消时释放连接、取消订阅和释放语句 |

## 版本与发布

当前发布线：核心 `6.0.0`，SQLite/PostgreSQL `4.0.0`，MySQL `5.0.0`；驱动依赖 `laconic: ^6.0.0`。

发布前校验：

```bash
dart pub get
dart analyze
docker compose up -d --wait
dart test packages/laconic/test packages/laconic_sqlite/test \
  packages/laconic_mysql/test packages/laconic_postgresql/test --concurrency=1
docker compose down
```

各包独立发布，先发布 `laconic`，再发布三个驱动包。发布前可在各包目录运行
`dart pub publish --dry-run` 检查内容；正式发布需由维护者执行。
完整步骤见根目录 [RELEASE.md](RELEASE.md)。
CHANGELOG 必须记录 breaking changes、迁移说明和驱动版本对应关系。

## 依赖

### 核心包（`packages/laconic`）
- 零运行时依赖。开发依赖：`lints: ^5.1.1`、`test: ^1.25.15`。

### SQLite 驱动
- `sqlite3: ^3.3.2` — 通过 `dart:ffi` 使用原生 SQLite。使用 `Database.prepare()` 进行参数化语句。

### MySQL 驱动
- `buffer: ^1.1.1`、`crypto: ^3.0.1` — 内嵌纯 Dart MySQL 客户端的字节编码与认证摘要支持；不再依赖外部 `mysql_client`。

### PostgreSQL 驱动
- `postgres: ^3.5.4` — PostgreSQL 客户端，带 `Pool` 连接池。使用 `Session.prepare()`（扩展查询协议）。
