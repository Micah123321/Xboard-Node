> **@status:** completed | 2026-04-15 21:55

@feature: install-http01-preflight
@created: 2026-04-15 21:42
@status: completed
@mode: R2-INTERACTIVE

# 进度概览

- completed: 4
- failed: 0
- skipped: 0
- pending: 0
- total: 4

# 任务列表

- [√] 1.1 在 `install.sh` 中补充 HTTP-01 约束说明与预检提示，明确公网 80 约束和 `--cert-http-port` 的真实语义 | depends_on: []
- [√] 1.2 在 `install.sh` 中增强部署结果与证书排障输出，覆盖自定义监听端口场景 | depends_on: [1.1]
- [√] 2.1 同步更新 `README.md` 与 `config.yml.example` 的 HTTP-01 说明，避免误导为任意公网端口验证 | depends_on: [1.2]
- [√] 2.2 运行脚本/测试验证，确认包和代码行为一致 | depends_on: [2.1]

# 执行日志

- 2026-04-15 21:42 完成 `install.sh` 的 HTTP-01 语义收口：新增本地监听检查、80 转发提示、部署摘要增强与交互文案修正。
- 2026-04-15 21:43 已同步更新 `README.md`、`config.yml.example`、`.helloagents/modules/config.md`、`.helloagents/modules/docs.md`。
- 2026-04-15 21:44 已执行 `wsl bash -lc "tr -d '\\r' < /mnt/e/code/go/Xboard-Node/install.sh | bash -n"` 与 `git diff --check -- install.sh README.md config.yml.example`；语法检查通过，`diff --check` 仅返回现有 LF/CRLF 警告。

# 执行备注

- `install-http01-preflight#D001`: 不伪造“任意公网端口 HTTP-01”能力，改为增强预检与提示。
- 本轮未改动 `internal/cert/cert.go` 的 ACME 实现；继续沿用现有 `AltHTTPPort` 行为，只在安装层把约束说明清楚。
