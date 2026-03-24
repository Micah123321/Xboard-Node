@feature: install-ss-egress-healthcheck
@created: 2026-03-25 05:40
@status: completed
@mode: R2-INTERACTIVE

# 进度概览

- completed: 4
- failed: 0
- skipped: 0
- pending: 0
- total: 4

# 任务列表

- [√] 1.1 在 `install.sh` 中新增 `singbox + --egress-shadowsocks-uri` 启动后 probe 等待与日志解析逻辑 | depends_on: []
- [√] 1.2 在 `install.sh` 中补失败收口：输出失败摘要、排查命令并返回非零退出码，同时保留已部署节点现场 | depends_on: [1.1]
- [√] 1.3 为 `README.md` 增量补充安装脚本健康检查行为说明，避免继续把 SS 上游超时误解为部署成功 | depends_on: [1.2]
- [√] 1.4 运行定向验证并同步 `.helloagents/CHANGELOG.md` / 方案包执行记录 | depends_on: [1.3]

# 执行日志

- 2026-03-25 05:40 因本机无可用 `python` 入口，按 HelloAGENTS 降级为手动创建方案包。
- 2026-03-25 05:5x 完成 `install.sh` 启动后 SS egress 健康检查与失败收口，`README.md` 增量补充行为说明。
- 2026-03-25 05:5x 已执行 `bash -n install.sh` 与 `git diff --check`；当前工作站未运行 Linux 节点实例，未做真实部署回放。

# 执行备注

- 本轮只收口安装脚本部署体验，不改 `internal/service` 或 `internal/kernel` 的 probe 实现。
- 若后续需要覆盖 `xray`，应先补等价的运行态探测能力，再决定是否在安装脚本统一启用强校验。
