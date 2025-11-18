# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

Laconic 是一个类似 Laravel 的 SQL 查询构建器库，用 Dart 编写，支持 MySQL 和 SQLite 数据库。它提供了链式 API 来构建和执行 SQL 查询。

**依赖说明**: 本项目依赖 Flutter SDK。确保系统已安装 Flutter 环境后再进行开发。

## 常用命令

### 依赖管理
```bash
# 安装依赖（需要先安装 Flutter SDK）
dart pub get
```

### 测试
```bash
# 运行所有测试
dart test

# 运行单个测试文件
dart test test/laconic_test.dart

# 运行特定测试（使用 --name 参数匹配测试名称）
dart test --name "select * from users"
```

### 代码分析
```bash
# 运行静态分析
dart analyze

# 格式化代码
dart format .

# 格式化特定文件
dart format lib/src/query_builder/query_builder.dart
```

## 核心架构

### 1. Grammar 模式（受 Laravel 启发）

核心查询构建使用 Grammar 模式，与 Laravel 的实现类似：
- **QueryBuilder 层**: 存储查询组件（`lib/src/query_builder/query_builder.dart`）
  - 直接存储查询的各个部分（columns, wheres, joins, orders 等）
  - 提供流式 API 方法来构建查询
- **Grammar 层**: 将查询组件编译为数据库特定的 SQL（`lib/src/query_builder/grammar/`）
  - `Grammar`: 抽象基类，定义编译接口
  - `SqlGrammar`: SQL 实现（用于 MySQL 和 SQLite）
  - `CompiledQuery`: 封装编译后的 SQL 和绑定参数
- **JoinClause**: 辅助类，用于构建 JOIN 条件

### 2. 查询构建流程

1. `Laconic.table(name)` → 创建 `QueryBuilder` 实例
2. 链式方法调用 → 存储查询组件到内部数据结构（例如 `.where()`, `.join()`, `.orderBy()`）
3. 终端方法调用 → Grammar 编译组件为 SQL 和绑定参数
4. 执行 SQL → 通过 `Laconic._execute()` 使用相应的数据库驱动

### 3. 数据库驱动层

- `LaconicDriver`: 枚举类型（`mysql`, `sqlite`）
- `Laconic`: 主类，管理数据库连接和查询执行
  - MySQL: 使用 `MySQLConnectionPool`（来自 `mysql_client` 包）
  - SQLite: 使用 `Database`（来自 `sqlite3` 包）
- 配置类: `MysqlConfig`, `SqliteConfig`

### 4. 关键特性

- **事务支持**: `Laconic.transaction()` 方法支持 MySQL 和 SQLite
- **查询监听**: 通过 `listen` 回调可以记录所有执行的 SQL（用于调试）
- **结果封装**: `LaconicResult` 类封装查询结果，支持从不同驱动转换

## 代码修改注意事项

### 添加新的 SQL 特性

1. 在 `QueryBuilder` 中添加字段存储新的查询组件
2. 在 `QueryBuilder` 中添加链式方法来设置该组件
3. 在 `Grammar.compileSelect()` 或其他编译方法中添加编译逻辑
4. 在 `SqlGrammar` 中实现具体的 SQL 生成逻辑
5. 在 `test/laconic_test.dart` 中添加测试用例

示例：添加 `DISTINCT` 支持
```dart
// 1. 在 QueryBuilder 中添加字段
bool _distinct = false;

// 2. 添加方法
QueryBuilder distinct() {
  _distinct = true;
  return this;
}

// 3. 在 SqlGrammar.compileSelect() 中
buffer.write(_distinct ? 'select distinct ' : 'select ');
```

### 添加新的数据库驱动

1. 在 `LaconicDriver` 枚举中添加新驱动
2. 创建配置类（参考 `MysqlConfig`, `SqliteConfig`）
3. 在 `lib/src/query_builder/grammar/` 中创建新的 Grammar 类（如果 SQL 方言不同）
4. 在 `Laconic._execute()` 中添加驱动分支
5. 在 `QueryBuilder` 构造函数中根据驱动选择合适的 Grammar

### 设计原则

- **简单优于复杂**: 使用直接的数据结构而非复杂的抽象
- **与 Laravel 保持一致**: 功能和 API 设计应参考 Laravel Query Builder
- **避免过度工程**: 只在真正需要时才添加抽象层

## 代码风格

- 使用 `package:lints/recommended.yaml` 规则集
- 所有公共 API 应该有文档注释
- 使用 `dart format` 保持代码格式一致
