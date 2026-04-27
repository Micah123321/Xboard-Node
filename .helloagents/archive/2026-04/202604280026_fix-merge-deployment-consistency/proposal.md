# 变更提案: fix-merge-deployment-consistency

## 元信息
```yaml
类型: 修复/重构
方案类型: implementation
优先级: P0
状态: 已确认
创建: 2026-04-28
```

---

## 1. 需求

### 背景
`cedar2025/dev` 合并后，核心 Go 代码已经能编译并通过测试，但部署入口仍存在不一致：

- 项目已完成 `xboard-node` 到 `mi-node` 的命名切换，知识库要求编译产物、安装目录、systemd 服务名、容器名与 CI artifact 统一为 `mi-node`。
- upstream 新增了 `RootConfig`、`instances:`、machine mode、`xbctl` 和新安装流程，但当前 `cmd/mi-node` 仍只加载 legacy `Config`。
- `install.sh` 混入 upstream 新流程后出现变量/函数不完整、命名不一致风险。
- `cmd/xbctl` 默认仍操作 `/etc/xboard-node`、`xboard-node.service`、`/usr/local/bin/xboard-node`。
- xray 的协议声明与配置生成不一致，可能误拒绝已实现的 `socks` / `http` 节点。
- 文档未反映 DNS provider、custom route 优先级、machine/instances 和部署工具的真实状态。

### 目标
- 让 `cmd/mi-node` 正式接入 `RootConfig`，兼容 legacy 单节点、`nodes:`、`instances:` 与 machine mode。
- 将 `install.sh` 和 `xbctl` 统一到 `mi-node` 路径、服务名、二进制名和发布 artifact。
- 修复 xray 协议能力声明，避免运行时校验误伤。
- 更新示例和文档，使部署方式、DNS provider、custom route/custom outbound、machine/instances 与代码一致。
- 通过 Go 测试、入口构建、脚本语法检查和关键文本检查。

### 约束条件
```yaml
时间约束: 本轮完成端到端修复和验证
性能约束: 不引入额外常驻轮询或阻塞启动路径；machine mode 按现有 upstream 间隔策略运行
兼容性约束:
  - 保留现有 mi-node legacy config.yml 单节点/多 nodes 部署方式
  - 保留 /etc/mi-node、mi-node.service、/usr/local/bin/mi-node 命名体系
  - 不回退本地模块路径 github.com/micah123321/mi-node
业务约束:
  - 不推送远端
  - 不执行生产安装/卸载/重启命令
```

### 验收标准
- [ ] `cmd/mi-node` 使用 `LoadRoot` / `NormalizeInstances` / `WatchConfigRoot`，并能启动 legacy、instances 和 machine 实例。
- [ ] `install.sh` 的参数变量、action 分发、服务/路径/二进制命名一致，`bash -n` 语法通过。
- [ ] `xbctl` 默认路径、服务名、二进制名、下载 artifact、帮助文案统一为 `mi-node`。
- [ ] xray 协议声明与配置生成一致，不误拒绝 `socks` / `http`。
- [ ] `config.yml.example` 和 docs 更新到当前能力；不再发布错误的 `xboard-node` 部署路径。
- [ ] `go test ./...`、关键构建命令和脚本检查通过。

---

## 2. 方案

### 技术方案
采用“完整接入 `mi-node` 部署体系”方案：

- 入口层：以 upstream `cmd/xboard-node/main.go` 的 `RootConfig`/machine/instances 编排为基础，迁移到本地 `cmd/mi-node/main.go`，同时保留本地 debug egress endpoint。
- 工具层：将 `cmd/xbctl` 的路径、service、binary、release artifact、帮助文案全部切到 `mi-node`；保持命令行为不变。
- 安装层：修复 `install.sh` 的变量命名、action 默认值、缺失函数、路径和服务命名；对尚未完成的 Docker/旧子命令路径保守处理，保证 native install/upgrade/uninstall/status 逻辑可用且不误指向旧名称。
- 内核校验层：修复 xray `Protocols()`，让运行时校验与现有 config builder 对齐。
- 文档层：同步 `config.yml.example`、custom route/outbound、DNS provider 和部署说明，明确新能力与旧部署兼容关系。

### 影响范围
```yaml
涉及模块:
  - cmd/mi-node: 启动入口、热重载、health/debug、instances/machine 调度
  - cmd/xbctl: 管理工具默认路径、服务名、artifact、帮助文案
  - install.sh: 安装/升级/卸载/status 流程和命名一致性
  - internal/kernel/xray: 协议能力声明
  - docs/config: 示例和操作说明
  - .helloagents: 方案包、CHANGELOG、模块知识同步
预计变更文件: 10-16
```

### 风险评估
| 风险 | 等级 | 应对 |
|------|------|------|
| 启动入口改动影响 legacy config | 高 | 保留 `NormalizeInstances()` 对 legacy 配置的兼容；补入口测试或最小构建验证 |
| `install.sh` 仍有未覆盖路径 | 高 | 语法检查 + 关键变量检查；不执行真实安装；文档标明支持范围 |
| `xbctl` 操作系统路径有外部副作用 | 中 | 只改代码不执行系统命令；通过文本和 Go 构建验证 |
| machine mode 依赖面板 v2 API | 中 | 代码接入但不做真实外部 API 验证；文档说明面板需支持 v2/machine |
| DNS provider 文档与 provider env 不一致 | 中 | 以 `internal/cert/dnsproviders` 代码为准同步 |

### 方案取舍
```yaml
唯一方案理由: 用户要求“完整修复”，且项目知识库明确要求全量统一到 mi-node；只保守回退会留下 upstream 新能力半合入，双轨兼容会继续制造部署路径歧义。
放弃的替代路径:
  - 保守回退到旧部署方式: 无法消化已合入的 machine/xbctl/install 改造，后续仍需二次迁移
  - 保留 mi-node/xboard-node 双轨: 与项目命名约束冲突，容易造成用户操作错服务或目录
回滚边界: 可通过安全分支 backup/pre-merge-20260427-234942 回到合并前；本方案代码改动也会独立提交，必要时可 revert 本轮修复提交。
```

---

## 3. 技术设计

### 架构设计
```mermaid
flowchart TD
    A[cmd/mi-node] --> B[config.LoadRoot]
    B --> C[NormalizeInstances]
    C --> D{Instance Mode}
    D -->|node| E[service.New per node]
    D -->|machine| F[machine.New orchestrator]
    E --> G[Kernel sing-box/xray]
    F --> E
    H[xbctl/install.sh] --> I[/etc/mi-node + mi-node.service]
```

### 数据模型
| 字段 | 类型 | 说明 |
|------|------|------|
| `RootConfig.instances` | `[]Config` | 多实例配置入口，legacy 配置为空时仍使用嵌入 `Config` |
| `Config.machine` | `*MachineConfig` | machine mode 标识，驱动 machine orchestrator |
| `Config.nodes` | `[]NodeEntry` | legacy 多节点模式，仍由单个 instance 展开 |

---

## 4. 核心场景

### 场景: legacy 单节点部署
**模块**: `cmd/mi-node`, `config`, `service`
**条件**: `config.yml` 顶层包含 `panel.url/token/node_id`
**行为**: `LoadRoot` 读取为单个 legacy instance，启动一个 `Service`
**结果**: 与合并前部署方式一致。

### 场景: instances 多实例部署
**模块**: `cmd/mi-node`, `config`
**条件**: `config.yml` 包含 `instances:`
**行为**: 每个 instance 独立校验、独立启动，避免 health port、config_dir、node binding 冲突
**结果**: 单进程可管理多个 panel/node 绑定。

### 场景: machine mode
**模块**: `cmd/mi-node`, `internal/machine`, `panel`
**条件**: instance 配置 `machine.machine_id` 与 token
**行为**: machine orchestrator 发现节点并为每个节点启动 service
**结果**: 支持面板 machine API 动态管理节点。

### 场景: 管理工具统一命名
**模块**: `cmd/xbctl`, `install.sh`
**条件**: 用户使用 installer 或 `xbctl`
**行为**: 工具只操作 `/etc/mi-node`、`mi-node.service`、`/usr/local/bin/mi-node`
**结果**: 不会误创建或操作 `xboard-node` 路径。

---

## 5. 技术决策

### fix-merge-deployment-consistency#D001: 以 mi-node 单轨承接 upstream 新能力
**日期**: 2026-04-28
**状态**: ✅采纳
**背景**: 合并后 upstream 新能力和本地重命名部署体系发生冲突。
**选项分析**:
| 选项 | 优点 | 缺点 |
|------|------|------|
| A: 完整接入 mi-node 单轨 | 彻底消除路径/服务名歧义，可发布 | 改动较大，需要更完整验证 |
| B: 保守回退旧部署 | 风险低 | 新能力半合入，后续仍需迁移 |
| C: mi-node/xboard-node 双轨 | 跟 upstream 容易 | 与项目命名约束冲突，部署风险高 |
**决策**: 选择方案 A
**理由**: 满足用户“完整修复”要求，且符合知识库中 `mi-node` 命名约束。
**影响**: `cmd/mi-node`、`cmd/xbctl`、`install.sh`、文档和验证流程。

---

## 6. 验证策略

```yaml
verifyMode: test-first
reviewerFocus:
  - cmd/mi-node 入口是否兼容 legacy config 和 RootConfig
  - install.sh 是否仍有 xboard-node 名称或未定义变量/函数
  - xbctl 是否统一到 mi-node 路径
  - xray 协议声明是否与 builder 一致
testerFocus:
  - go test ./...
  - go test ./cmd/mi-node ./cmd/xbctl ./internal/config ./internal/kernel/xray ./internal/service
  - go build ./cmd/mi-node
  - go build ./cmd/xbctl
  - bash -n install.sh
  - rg "xboard-node|/etc/xboard-node|xboard-node.service" install.sh cmd/xbctl/main.go cmd/mi-node/main.go
uiValidation: none
riskBoundary:
  - 不执行真实 systemctl/install/uninstall/upgrade 命令
  - 不推送远端
  - 不删除用户文件
```

---

## 7. 成果设计

N/A。本任务不涉及视觉/UI 产出。
