# Release checklist

当前发布线：`laconic 6.0.0`、`laconic_sqlite 4.0.0`、`laconic_mysql 5.0.0`、
`laconic_postgresql 4.0.0`；新增 `laconic_mariadb 1.0.0`、`laconic_sqlserver 1.0.0`（尚未发布）。驱动依赖 `laconic: ^6.0.0`。

## 1. 发布前条件

- [ ] 记录查询返回值与游标输出的 breaking changes：min/max 为 Object?、sum 空结果为 0、批量/子查询写入返回行数、existsOr 回调化，以及 LaconicCursor 双向复合分页；发布前同步驱动最低核心版本与调用迁移说明

- [ ] 移除 `raw()` 属于 breaking change：确定核心下一主版本，并协调驱动最低核心版本；升级调用为 `Expression()`，CLI 调用和配置按 MIGRATIONS.md 迁移

- [ ] 为 Schema Builder、Migration 和 CLI 确定核心发布版本，并同步所有驱动的最低核心依赖版本；已发布的 6.0.0 不包含这些 API
- [ ] Blueprint 快捷方法和高级类型新增 ColumnType 枚举值及类型参数；同步各驱动及第三方穷尽 switch，保留 signed ID 与现有默认映射，核对 SCHEMA.md 的 unsigned、时区、CHECK 枚举和 PostGIS 限制
- [ ] 同步第二阶段 Schema 核心/驱动版本：全文索引、索引重命名与删除、列修饰和生成列；第三方同步 computed/fullText/SchemaChange 枚举、新编译钩子，以及 SchemaTransactionDriver 的 disableForeignKeys 命名参数。核对 MariaDB nullable 生成列、PostgreSQL stored 基线和 SQLite 原子索引替换限制
- [ ] 迁移 CLI 新增 reset/refresh/fresh、batch/pretend；生产环境脚本需加 `--force`。发布匹配的核心与 SQLite grammar wipe 实现，核对 MIGRATIONS.md 的清表范围和预览限制
- [ ] 同步第三方 `compileAlterTable` 覆盖方法的列/对象快照参数，记录 `change()`、元数据接口及可选 `SchemaTransactionDriver` 的扩展契约
- [ ] 记录 `implements SqlGrammar` 实现者必须补齐新增成员的兼容性变更
- [ ] 为核心新增的 `compileAggregateExpression` 确定发布版本，并同步新驱动的最低核心依赖版本；SQL Server 驱动不能使用缺少该钩子的旧核心
- [ ] 工作区已提交且 `git status` 干净
- [ ] 六个 `pubspec.yaml` 的 `version` 与驱动依赖约束一致
- [ ] 六个 `CHANGELOG.md` 已包含当前版本的 breaking changes / 功能 / 修复
- [ ] README（英文与中文）的版本号、安装片段和升级说明已更新
- [ ] Docker 可运行（MySQL 3306、MariaDB 3307、PostgreSQL 5433、SQL Server 1433）

- [ ] 第三阶段迁移能力需匹配核心与全部五个驱动：新增可选 `MigrationLockDriver` / `SchemaStateDriver`；原生 dump 客户端必须与服务器版本兼容，SQL Server 不提供 dump/load。验证 `--prune` 的文件删除和基线回滚限制，保留现有跨库差异约定。

- [ ] 第四阶段查询便捷 API 位于未发布核心：相对日期条件、降序分块、`chunkMap`、`tap/pipe`、`rawValue` 及 QueryBuilder EXISTS。无需新增驱动协议，但需五库共享回归；核对日期时钟/秒精度约定与游标缺列异常改为 `LaconicException`。

## 2. 完整校验

从 workspace 根目录执行：

```bash
dart pub get
dart analyze
docker compose up -d --wait
dart test packages/laconic/test packages/laconic_sqlite/test \
  packages/laconic_mysql/test packages/laconic_postgresql/test \
  packages/laconic_mariadb/test packages/laconic_sqlserver/test --concurrency=1
docker compose down
```

SQL Server 容器需要 x86-64 Linux；Apple Silicon 上的模拟运行不属于微软官方支持环境。

## 3. 发布内容 dry-run

在六个包目录分别执行：

```bash
cd packages/laconic && dart pub publish --dry-run
cd packages/laconic_sqlite && dart pub publish --dry-run
cd packages/laconic_mysql && dart pub publish --dry-run
cd packages/laconic_postgresql && dart pub publish --dry-run
cd packages/laconic_mariadb && dart pub publish --dry-run
cd packages/laconic_sqlserver && dart pub publish --dry-run
```

预期仅出现 “checked-in files are modified” 警告（如果尚未提交）。
其他警告需要先处理。

## 4. 发布顺序

pub.dev 上驱动依赖 `laconic: ^6.0.0`，因此必须先发布核心包：

1. 打标签（如果仓库使用统一版本标签）：
   ```bash
   git tag v6.0.0
   git push origin v6.0.0
   ```
2. 发布核心包：
   ```bash
   cd packages/laconic
   dart pub publish
   ```
3. 确认 https://pub.dev/packages/laconic/versions/6.0.0 可用。
4. 依次发布驱动：
   ```bash
   cd packages/laconic_sqlite && dart pub publish
   cd ../laconic_mysql && dart pub publish
   cd ../laconic_postgresql && dart pub publish
   cd ../laconic_mariadb && dart pub publish
   cd ../laconic_sqlserver && dart pub publish
   ```
5. 在 GitHub 创建 release，链接六个 CHANGELOG 和 README 的升级章节。

## 5. 发布后验证

```bash
mkdir /tmp/laconic_release_check && cd /tmp/laconic_release_check
dart create -t console . 
dart pub add laconic:^6.0.0 laconic_sqlite:^4.0.0 \
  laconic_mysql:^5.0.0 laconic_postgresql:^4.0.0 \
  laconic_mariadb:^1.0.0 laconic_sqlserver:^1.0.0
dart analyze
```

再检查 pub.dev 页面、安装片段和 API 文档是否正常。

## 6. 回滚

pub.dev 不允许重新发布同一个版本。若发现问题，应在 pub.dev 上 retract 该版本，
修复后发布新的 patch 版本，并更新 CHANGELOG。驱动包的回滚同样需要新版本号。
