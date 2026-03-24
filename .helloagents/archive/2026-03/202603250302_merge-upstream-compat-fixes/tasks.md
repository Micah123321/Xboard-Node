@feature: merge-upstream-compat-fixes
@created: 2026-03-25 03:02
@status: completed
@mode: R3-INTERACTIVE

# 进度概览

- completed: 4
- failed: 0
- skipped: 0
- pending: 0
- total: 4

# 任务列表

- [√] 1.1 提取并复核上游 8 个提交的实际变更内容，确认仅保留协议兼容性相关改动 | depends_on: []
- [√] 1.2 将上游 `Shadowsocks` / `SS2022` / `Trojan` 兼容性修复手工整合到本地 `singbox` / `xray` 相关代码 | depends_on: [1.1]
- [√] 1.3 对因整合产生的测试或文档差异做最小同步，补齐必要回归用例 | depends_on: [1.2]
- [√] 1.4 运行定向验证，确认本地已有 `egress.shadowsocks` 改动与上游兼容性修复可共存 | depends_on: [1.3]

# 执行日志

- 2026-03-25 03:02 创建方案包，进入交互式执行。
- 2026-03-25 03:08 完成上游 8 个提交价值筛选，确定仅吸收协议兼容性相关修复，开始代码整合。
- 2026-03-25 03:18 已合入 `xray` 传统 Shadowsocks 多用户结构、`singbox/xray` Trojan TLS 兜底、`grpc serviceName` 兼容，并通过 `internal/kernel/singbox` / `internal/kernel/xray` 定向测试。
- 2026-03-25 03:24 完成 `go test ./internal/config ./internal/kernel/singbox ./internal/kernel/xray`，确认本地 `egress.shadowsocks` 与本次兼容性修复可共存。

# 执行备注

- 当前策略为“本地主线 + 选择性吸收上游协议兼容性修复”，暂不纳入 `nlog`、配置热重载、service/tracker 并发重构。
