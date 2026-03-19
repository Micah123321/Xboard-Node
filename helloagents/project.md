# 项目技术约定

---

## 技术栈
- **核心语言:** Go 1.25.x
- **主要依赖:** `sing-box`、`xray-core`、`gorilla/websocket`、`yaml.v3`
- **部署方式:** 单二进制运行，支持 `systemd` 原生部署和 Docker 容器部署

---

## 开发约定
- **代码组织:** 入口位于 `cmd/xboard-node`，核心逻辑集中在 `internal/`
- **配置格式:** 使用 YAML，必要字段可由环境变量覆盖
- **命名约定:** 导出标识符使用 PascalCase，包内标识符遵循 Go 社区习惯

---

## 错误与日志
- **错误处理:** 配置加载、内核启动、面板握手失败时直接返回错误并中止启动
- **日志体系:** 使用 `log/slog`，支持 `debug/info/warn/error`
- **日志输出:** 默认写入标准输出，可配置为文件

---

## 测试与流程
- **测试:** 使用 `go test ./...` 执行单元测试
- **发布:** 可通过 GitHub Releases 分发 Linux 二进制
- **运维:** 推荐优先使用原生二进制 + `systemd`，内存紧张场景可结合 `runtime.gomemlimit` 与 `runtime.gogc`