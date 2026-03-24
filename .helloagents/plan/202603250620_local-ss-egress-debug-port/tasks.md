@feature: local-ss-egress-debug-port
@created: 2026-03-25 06:20
@status: completed
@mode: R2-INTERACTIVE

# 进度概览

- completed: 4
- failed: 0
- skipped: 0
- pending: 0
- total: 4

# 任务列表

- [√] 1.1 新增 `debug_port` 配置字段、默认值与校验，并补 `internal/config` 最小回归测试 | depends_on: []
- [√] 1.2 为 `sing-box + kernel.egress.shadowsocks` 增加默认出站真实 probe、服务层调试状态与启动/重载日志 | depends_on: [1.1]
- [√] 1.3 在 `cmd/xboard-node/main.go` 挂载仅监听 `127.0.0.1` 的本地 HTTP 调试端口，返回每个 node 的 egress 调试状态 | depends_on: [1.2]
- [√] 1.4 运行定向验证并同步 `config.yml.example` / `README.md` / `.helloagents/CHANGELOG.md` | depends_on: [1.3]

# 执行日志

- 2026-03-25 06:20 创建方案包，范围限定为 sing-box 场景下的本地调试端口、SS 默认出站运行态探测和最小日志增强。
- 2026-03-25 06:45 完成 `debug_port`、本地 `127.0.0.1` HTTP 调试接口、sing-box 默认出站真实 probe、启动/重载日志与定向回归测试。

# 执行备注

- 本轮不扩展到 `xray`、不改现有 `health_port` 语义。
