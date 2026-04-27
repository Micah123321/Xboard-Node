# 任务清单: fix-merge-deployment-consistency

> **@status:** completed | 2026-04-28 00:56

```yaml
@feature: fix-merge-deployment-consistency
@created: 2026-04-28
@status: completed
@mode: R2-INTERACTIVE
```

## LIVE_STATUS
```json
{"status":"completed","completed":6,"failed":0,"pending":0,"total":6,"percent":100,"current":"全量验证通过，准备归档方案包","updated_at":"2026-04-28 01:20:00"}
```

## 进度概览

| 完成 | 失败 | 跳过 | 总数 |
|------|------|------|------|
| 6 | 0 | 0 | 6 |

---

## 任务列表

### 1. 运行入口

- [√] 1.1 修复 `cmd/mi-node/main.go` 的 RootConfig / instances / machine 接入
  - 预期变更: 将 legacy `config.Load` 启动流程迁移为 `config.LoadRoot` + `NormalizeInstances`，接入 `machine.New`，保留现有 health/debug endpoint 和 runtime tuning。
  - 完成标准: legacy 单节点、`nodes:`、`instances:`、machine mode 均有明确启动分支；不再需要 `cmd/xboard-node` 入口。
  - 验证方式: `go test ./cmd/mi-node`、`go build ./cmd/mi-node`
  - depends_on: []

### 2. 部署工具

- [√] 2.1 修复 `cmd/xbctl/main.go` 的 mi-node 命名和路径
  - 预期变更: 默认 config/meta/credentials/binary/service/install root/download artifact/help 文案全部统一为 `mi-node`。
  - 完成标准: `cmd/xbctl/main.go` 不再包含 `xboard-node` 部署路径或服务名；命令行为仍可构建。
  - 验证方式: `go test ./cmd/xbctl`、`go build ./cmd/xbctl`、`rg "xboard-node|/etc/xboard-node|xboard-node.service" cmd/xbctl/main.go`
  - depends_on: []

- [√] 2.2 修复 `install.sh` 的 action、变量、函数和 mi-node 命名一致性
  - 预期变更: 统一 `TOKEN`/`PANEL_TOKEN`、`GOMEMLIMIT`/`RUNTIME_GOMEMLIMIT`、action 默认值、status/uninstall 函数、service/binary/config/credential 路径和帮助文案。
  - 完成标准: `install.sh` 语法通过，native install/upgrade/uninstall/status 分支不会引用缺失变量/函数或旧 `xboard-node` 服务路径。
  - 验证方式: `bash -n install.sh`，以及文本搜索关键旧名称和未定义 action 变量。
  - depends_on: [2.1]

### 3. 运行时一致性

- [√] 3.1 修复 `internal/kernel/xray/xray.go` 协议能力声明
  - 预期变更: `Protocols()` 与 `internal/kernel/xray/config.go` 已实现 inbound builder 保持一致。
  - 完成标准: xray 的 `socks` / `http` 不被 `validateNodeRuntime` 误拒绝；未实现协议不被误声明。
  - 验证方式: `go test ./internal/kernel/xray ./internal/service`
  - depends_on: []

### 4. 文档与知识库

- [√] 4.1 更新 `config.yml.example` 和 docs，反映 DNS provider、custom route 优先级、machine/instances、mi-node 部署工具
  - 预期变更: 示例和文档以代码事实为准；不再传播错误 `xboard-node` 路径；新增能力标注面板/API 前提。
  - 完成标准: 文档与当前代码一致；关键术语和路径统一为 `mi-node`。
  - 验证方式: 文本搜索旧名称，人工核对文档与代码对应关系。
  - depends_on: [1.1, 2.1, 2.2, 3.1]

### 5. 验收

- [√] 5.1 执行全量验证并同步知识库/变更记录
  - 预期变更: 运行 Go 测试、构建、脚本语法、关键文本检查；更新 `.helloagents` 模块文档和 CHANGELOG。
  - 完成标准: 验证通过或明确记录残余风险；方案包任务状态完整。
  - 验证方式: `go test ./...`、`go build ./cmd/mi-node`、`go build ./cmd/xbctl`、`bash -n install.sh`、`git status --short`
  - depends_on: [4.1]

---

## 执行日志

| 时间 | 任务 | 状态 | 备注 |
|------|------|------|------|
| 2026-04-28 00:26 | DESIGN | in_progress | 选择方案一，创建方案包并进入开发实施准备 |
| 2026-04-28 00:34 | 1.1 | completed | `cmd/mi-node` 已接入 `LoadRoot`/`WatchConfigRoot`/machine mode，`go test ./cmd/mi-node` 通过 |
| 2026-04-28 00:38 | 2.1 | completed | `cmd/xbctl` 已统一 `mi-node` 路径/服务/二进制，`go test ./cmd/xbctl` 通过 |
| 2026-04-28 00:52 | 2.2 | completed | `install.sh` 已收敛为 `mi-node.service` 原生安装器，`bash -n install.sh` 和帮助/status 分支轻量探测通过 |
| 2026-04-28 01:00 | 3.1 | completed | xray `Protocols()` 已补齐 socks/http；`/etc/xboard-node` Go 回退路径改为 `/etc/mi-node`；相关包测试通过 |
| 2026-04-28 01:12 | 4.1 | completed | README/config 示例/DNS provider/custom routes 文档已按当前代码和 `mi-node.service` 部署方式同步 |
| 2026-04-28 01:20 | 5.1 | completed | `go test ./...`、两个入口构建、`bash -n install.sh`、关键旧名称扫描和 `git diff --check` 通过；知识库与 CHANGELOG 已同步 |

---

## 执行备注

- 本轮不执行真实安装、升级、卸载或 systemd 操作。
- 子代理调用因当前会话未显式要求子代理/并行代理工作，由主代理直接执行。
