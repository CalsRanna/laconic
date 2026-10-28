# Release checklist

当前发布线：`laconic 6.0.0`、`laconic_sqlite 4.0.0`、`laconic_mysql 5.0.0`、
`laconic_postgresql 4.0.0`。驱动依赖 `laconic: ^6.0.0`。

## 1. 发布前条件

- [ ] 工作区已提交且 `git status` 干净
- [ ] 四个 `pubspec.yaml` 的 `version` 与驱动依赖约束一致
- [ ] 四个 `CHANGELOG.md` 已包含当前版本的 breaking changes / 功能 / 修复
- [ ] README（英文与中文）的版本号、安装片段和升级说明已更新
- [ ] Docker 可运行（MySQL 3306、PostgreSQL 5433）

## 2. 完整校验

从 workspace 根目录执行：

```bash
dart pub get
dart analyze
docker compose up -d --wait
dart test packages/laconic/test packages/laconic_sqlite/test \
  packages/laconic_mysql/test packages/laconic_postgresql/test --concurrency=1
docker compose down
```

## 3. 发布内容 dry-run

在四个包目录分别执行：

```bash
cd packages/laconic && dart pub publish --dry-run
cd packages/laconic_sqlite && dart pub publish --dry-run
cd packages/laconic_mysql && dart pub publish --dry-run
cd packages/laconic_postgresql && dart pub publish --dry-run
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
   ```
5. 在 GitHub 创建 release，链接四个 CHANGELOG 和 README 的升级章节。

## 5. 发布后验证

```bash
mkdir /tmp/laconic_release_check && cd /tmp/laconic_release_check
dart create -t console . 
dart pub add laconic:^6.0.0 laconic_sqlite:^4.0.0 \
  laconic_mysql:^5.0.0 laconic_postgresql:^4.0.0
dart analyze
```

再检查 pub.dev 页面、安装片段和 API 文档是否正常。

## 6. 回滚

pub.dev 不允许重新发布同一个版本。若发现问题，应在 pub.dev 上 retract 该版本，
修复后发布新的 patch 版本，并更新 CHANGELOG。驱动包的回滚同样需要新版本号。
