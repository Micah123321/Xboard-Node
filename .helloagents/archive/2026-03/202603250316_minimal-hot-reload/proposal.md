# 方案包：最小热重载

- 创建时间：2026-03-25 03:16
- 类型：implementation

## 1. 需求

### 背景

上游分支包含 `nlog + hot-reload + concurrency` 一整组大改。当前只希望吸收其中的 `hot-reload` 能力，并明确不引入 `nlog` 与运行态并发模型重构。

### 目标

- 配置文件变化后自动重新加载配置并重启节点服务
- 仅在新配置有效时才触发重启
- 新配置无效时保留旧实例继续运行
- 保持现有 `slog` 日志体系与 `service` 实现不变

### 约束

- 不引入 `internal/nlog`
- 不修改 `internal/service/service.go`、`internal/tracker/tracker.go`、`internal/kernel/*dispatcher*`
- 不实现无缝热更，仅接受短暂重启窗口
- 多节点模式按整组服务重启处理，不做单节点局部 reload

### 验收标准

- 新增配置 watcher 能在文件变化后回调最新合法配置
- `cmd/xboard-node` 在检测到新配置时会停止旧服务并按新配置重启
- 无效配置变更只记录错误，不中断当前运行实例
- 至少有一组 watcher 级最小测试通过

## 2. 方案

### 技术方案

- 在 `internal/config/watcher.go` 新增基于 `fsnotify` 的 debounce watcher
- 在 `cmd/xboard-node/main.go` 增加 `runWithReload()` 外层循环，负责：
  - 启动 health check
  - 启动当前配置对应的 service 实例
  - 监听信号与 watcher 回调
  - 在收到合法新配置后取消旧实例并重建
- 保留 `config.InitLogger()` 与 `applyRuntimeConfig()` 现有行为，仅在 reload 成功后重新应用
- 通过 `internal/config/watcher_test.go` 验证：
  - 合法配置修改会触发回调
  - 非法配置修改不会触发回调

### 影响范围

- 入口：`cmd/xboard-node/main.go`
- 配置：`internal/config/watcher.go`
- 测试：`internal/config/watcher_test.go`
- 文档/知识库：`.helloagents/CHANGELOG.md`、`.helloagents/modules/config.md`

### 风险

- watcher 行为依赖文件系统事件，测试需要 debounce 与超时控制，避免脆弱性
- 采用整组 service 重启而非无缝 reload，切换时会有短暂空窗
- health check 端口变更需要在 reload 时正确重绑，避免端口占用残留
