# 任务清单: egress management

> **@status:** completed | 2026-04-28 14:11

```yaml
@feature: egress management
@created: 2026-04-28
@status: completed
@mode: R2
```

## 进度概览

| 完成 | 失败 | 跳过 | 总数 |
|------|------|------|------|
| 6 | 0 | 0 | 6 |

---

## 任务列表

### 1. xbctl 落地管理

- [√] 1.1 在 `cmd/xbctl/main.go` / `cmd/xbctl/egress.go` 中新增 `egress list/set/clear`
  - 预期变更: 支持按 `--node-id` / `--instance-id` 定位实例，设置 SOCKS5 或 Shadowsocks URI，清除默认出站，默认重启服务并支持 `--no-restart`
  - 完成标准: 配置写回只影响目标实例；SOCKS5 与 Shadowsocks 保持互斥；输出不泄露密码
  - 验证方式: `go test ./cmd/xbctl`
  - depends_on: []

- [√] 1.2 在 `cmd/xbctl/main_test.go` 中补 egress 管理回归测试
  - 预期变更: 覆盖 SOCKS5 URL 设置、SS URI 切换、clear、list 脱敏、实例定位失败
  - 完成标准: 测试能证明 node `322` 这类已存在实例可被补写落地
  - 验证方式: `go test ./cmd/xbctl`
  - depends_on: [1.1]

### 2. 远程一键入口

- [√] 2.1 在 `install.sh` 中新增 `egress` action
  - 预期变更: `bash install.sh egress --node-id 322 --socks5-url ...` 可准备/复用 `xbctl` 并透传到 `xbctl egress`
  - 完成标准: 不破坏 install/status/update/uninstall/list/remove；支持 `clear` 和 `--no-restart`
  - 验证方式: `bash -n install.sh`
  - depends_on: [1.1]

### 3. 迁移补偿

- [√] 3.1 在 `scripts/migrate-to-mi-node.sh` 中同步迁移 `kernel.egress`
  - 预期变更: 读取结构化 SOCKS5、`socks5://...` URI 和 `kernel.egress.shadowsocks.uri`，转换为安装器参数；日志脱敏认证信息
  - 完成标准: 迁移 node `322` 时旧配置里的落地出站不会丢失
  - 验证方式: `bash -n scripts/migrate-to-mi-node.sh`，并用临时 YAML 验证解析函数
  - depends_on: [2.1]

### 4. 文档与知识库

- [√] 4.1 更新 `README.md`、`MIGRATE.md`、`.helloagents/CHANGELOG.md`、`.helloagents/modules/config.md`
  - 预期变更: 记录 `xbctl egress` / `install.sh egress` 用法、迁移 egress 行为和安全提示
  - 完成标准: 文档命令可直接复制，且不包含真实密钥
  - 验证方式: 文档检查与 `rg` 检查旧错误说法
  - depends_on: [1.1, 2.1, 3.1]

### 5. 验证与发布

- [√] 5.1 运行测试、构建、脚本语法检查并提交推送
  - 预期变更: 通过 `go test ./...`、双二进制 build、shell 语法检查、`git diff --check`
  - 完成标准: 本地工作区干净，提交推送到 `origin/dev`
  - 验证方式: `git status --short --branch` 和 `git log --oneline -1`
  - depends_on: [1.2, 4.1]

---

## 执行日志

| 时间 | 任务 | 状态 | 备注 |
|------|------|------|------|
| 2026-04-28 13:50 | 方案包 | in_progress | 创建 egress management 方案包 |
| 2026-04-28 14:05 | 1.1-4.1 | completed | 完成 xbctl/install/migrate/docs 实现 |
| 2026-04-28 14:08 | 5.1 | completed | go test/build、bash -n、git diff --check 通过 |

---

## 执行备注

- 用户选择完整落地管理方案：`xbctl egress set/list/clear` + `install.sh egress` 远程入口。
- 本轮已存在迁移脚本 egress 解析的未提交修改，将纳入 3.1 统一验收。
- 验证命令: `go test ./...`、`go build ./cmd/mi-node`、`go build ./cmd/xbctl`、`bash -n install.sh`、`bash -n scripts/migrate-to-mi-node.sh`、`git diff --check`。
