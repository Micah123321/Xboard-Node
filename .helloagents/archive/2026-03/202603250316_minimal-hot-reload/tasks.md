@feature: minimal-hot-reload
@created: 2026-03-25 03:16
@status: completed
@mode: R2-INTERACTIVE

# 进度概览

- completed: 4
- failed: 0
- skipped: 0
- pending: 0
- total: 4

# 任务列表

- [√] 1.1 新增最小配置 watcher，保证仅合法配置会触发回调 | depends_on: []
- [√] 1.2 改造 `cmd/xboard-node/main.go`，实现基于 watcher 的整组 service 重启 | depends_on: [1.1]
- [√] 1.3 补 watcher 最小回归测试，并验证非法配置不会打断旧实例链路假设 | depends_on: [1.2]
- [√] 1.4 运行定向测试并同步知识库记录 | depends_on: [1.3]

# 执行日志

- 2026-03-25 03:16 创建方案包，开始最小热重载实现。
- 2026-03-25 03:28 已实现 `slog + fsnotify` 最小热重载，合法配置变更触发整组 service 重启，非法配置变更仅记录错误并保留旧实例。
- 2026-03-25 03:31 完成 `go test ./internal/config ./internal/kernel/singbox ./internal/kernel/xray ./cmd/xboard-node`。

# 执行备注

- 本次只吸收 hot-reload，明确排除 `nlog` 与运行态并发重构。
