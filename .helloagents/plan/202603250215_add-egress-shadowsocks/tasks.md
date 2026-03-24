@feature: add-egress-shadowsocks
@created: 2026-03-25 02:15
@status: completed
@mode: R2-INTERACTIVE

# 进度概览

- completed: 3
- failed: 0
- skipped: 0
- pending: 0
- total: 3

# 任务列表

- [√] 1.1 梳理现有 `egress.socks5` 配置和双内核默认出站生成逻辑 | depends_on: []
- [√] 1.2 实现 `kernel.egress.shadowsocks` 配置、校验与双内核出站生成 | depends_on: [1.1]
- [√] 1.3 补测试、更新 README / `config.yml.example` 并完成验证 | depends_on: [1.2]

# 执行日志

- 2026-03-25 02:15 创建方案包，等待实现落地。
- 2026-03-25 02:24 完成 `internal/config`、`internal/kernel/singbox`、`internal/kernel/xray` 改造，并通过全仓 `go test ./...`。

# 执行备注

- 当前任务已完成，默认出站现在支持 `socks5` 与 `shadowsocks` 二选一。
