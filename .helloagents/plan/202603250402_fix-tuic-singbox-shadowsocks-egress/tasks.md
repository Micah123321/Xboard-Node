@feature: fix-tuic-singbox-shadowsocks-egress
@created: 2026-03-25 04:02
@status: completed
@mode: R2-INTERACTIVE

# 进度概览

- completed: 3
- failed: 0
- skipped: 0
- pending: 0
- total: 3

# 任务列表

- [√] 1.1 为 `tuic + kernel.egress.shadowsocks` 补最小回归测试，覆盖配置生成与默认最终出站选择 | depends_on: []
- [√] 1.2 复核 `internal/kernel/singbox` 运行路径，确认当前代码未复现“TUIC + SS 默认出站回退 direct”问题，本轮不修改运行逻辑 | depends_on: [1.1]
- [√] 1.3 运行定向验证并同步知识库/变更记录 | depends_on: [1.2]

# 执行日志

- 2026-03-25 04:02 创建方案包，范围限定为 sing-box 的 `tuic + shadowsocks egress` 运行态排查与最小回归补强。
- 2026-03-25 04:3x 在 `internal/kernel/singbox/config_test.go` 新增 `TestBuildConfig_TUICWithShadowsocksProxy`，验证 `route.final=default-shadowsocks` 且默认 SS outbound 被生成。
- 2026-03-25 04:3x 新增 `internal/kernel/singbox/tuic_with_quic_test.go`，在 `with_quic` 条件下启动真实 TUIC inbound，验证 `OutboundManager.Default()` 为 `default-shadowsocks`。
- 2026-03-25 04:4x 使用定向验证链路跑通静态回归与 `with_quic` 运行态回归，两组测试均通过。

# 执行备注

- 本轮未改动 sing-box 运行逻辑，因为当前代码路径下未复现默认 Shadowsocks 出站失效。
- 用户现场安装日志显示“`xboard-node` 二进制已存在，跳过下载”，线上机器存在继续运行旧二进制的风险，需要与代码版本分开判断。
