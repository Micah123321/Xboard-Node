# 方案包：本地 SS 出站调试端口

- 创建时间：2026-03-25 06:20
- 类型：implementation

## 1. 需求
### 背景

当前仓库已经支持 `kernel.egress.shadowsocks`，但在运行态缺少一个安全、可观测、可验证的调试入口。用户需要确认 `sing-box + tuic + egress.shadowsocks` 场景下默认出站是否真的走到了 SS/SS2022 上游，而不是只看静态配置文件。

### 目标

- 新增独立 `debug_port` 配置，默认关闭
- 调试端口仅监听 `127.0.0.1`
- 启动/重载时输出 egress.shadowsocks 相关摘要日志
- 暴露本地 HTTP 调试接口，返回：
  - 默认出站 tag
  - SS 上游地址与 method
  - 最近一次默认出站真实拨号检查结果

### 约束

- 仅修 `sing-box` 运行态，不扩大到 `xray`
- 不复用现有 `health_port`，避免语义和暴露范围混淆
- 不打印 SS 密码
- 拨号检查必须通过当前默认出站真实发起，而不是只检查上游端口可达

### 验收标准

- `config.Load()` 能解析并校验 `debug_port`
- `Service` 能在启用 `kernel.egress.shadowsocks` 时记录调试状态和最近探测结果
- `main.go` 能启动仅监听 `127.0.0.1:<debug_port>` 的本地 HTTP 调试端口
- 最小回归测试覆盖配置校验、调试状态/接口输出、sing-box 默认出站 probe 关键路径

## 2. 方案

### 技术方案

- 在 `internal/config/config.go` 新增顶层 `DebugPort int 'yaml:"debug_port"'`
- 在 `internal/service` 增加 egress 调试状态结构与只读导出方法
- 在 `internal/kernel/singbox` 增加默认出站探测方法，内部使用 `common/dialer.NewDefaultOutbound(...)`
- 在 `cmd/xboard-node/main.go` 增加独立的本地调试 HTTP server，返回 JSON 状态

### 影响范围

- 配置解析：`internal/config`
- sing-box 调试能力：`internal/kernel/singbox`
- 运行态服务与日志：`internal/service`
- 本地 HTTP 入口：`cmd/xboard-node`
- 示例配置/文档：`config.yml.example`、`README.md`

### 风险

- 调试探测如果依赖 DNS，会把 DNS 问题和出站问题混在一起；应优先使用固定 IP 目标
- reload 失败时不能污染上一次可用调试状态
- 多节点模式下需要稳定返回每个 node 的调试状态，不能只保留临时 service 引用
