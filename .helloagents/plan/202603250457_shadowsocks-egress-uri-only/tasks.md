@feature: shadowsocks-egress-uri-only
@created: 2026-03-25 04:57
@status: completed
@mode: R2-INTERACTIVE

# 进度概览

- completed: 3
- failed: 0
- skipped: 0
- pending: 0
- total: 3

# 任务列表

- [√] 1.1 重构 `internal/config/egress.go`，让 `kernel.egress.shadowsocks` 只接受 `uri`，并补齐传统 SS / SS2022 的 URI 解析与加载期校验 | depends_on: []
- [√] 1.2 调整 `install.sh` 只接受 `--egress-shadowsocks-uri`，删除旧拆分参数写入路径并更新错误文案 | depends_on: [1.1]
- [√] 1.3 补充最小回归测试并同步 `README.md`、`config.yml.example`、`.helloagents/CHANGELOG.md` | depends_on: [1.2]

# 执行日志

- 2026-03-25 04:57 创建方案包，范围限定为默认 Shadowsocks 出站改为仅接受 `ss://...` URI，并明确不再兼容旧拆分字段。
- 2026-03-25 05:10 完成 `internal/config` URI-only 解析改造、`install.sh` 参数切换、README/示例配置同步，以及定向测试 `go test ./internal/config ./internal/kernel/singbox ./internal/kernel/xray ./internal/service ./cmd/xboard-node`。

# 执行备注

- 双内核默认 Shadowsocks 出站生成逻辑已存在，本轮不改内核生成，只改输入层、脚本层、文档层和回归测试。
