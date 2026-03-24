# 项目上下文

## 基本信息

- 项目：Xboard-Node
- 仓库路径：`E:\code\go\Xboard-Node`
- 主要语言：Go
- 当前关注点：补齐跨 `sing-box` / `xray` 的默认 `egress` 出站能力

## 当前任务约束

- 现有默认出站仅支持 `kernel.egress.socks5`
- 新增 `kernel.egress.shadowsocks` 时，需保持默认路由语义与 `socks5` 一致
- 需同时支持传统 Shadowsocks 与 Shadowsocks 2022
