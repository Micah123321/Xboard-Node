# kernel 模块

## 职责

- 生成 `sing-box` 与 `xray` 的运行时配置
- 将面板配置和本地 `kernel.egress` 配置转换为内核原生 outbound / route

## 当前关键行为

- 默认出站仍保留 `direct` / `block` 基础结构
- 当配置 `kernel.egress.shadowsocks` 时，会生成 `default-shadowsocks` outbound
- `sing-box` 与 `xray` 对默认 Shadowsocks 出站保持一致的 tag 与路由语义
- `xray.Protocols()` 与已实现 inbound builder 保持一致：`vmess`、`vless`、`trojan`、`shadowsocks`、`socks`、`http`、`hysteria`
- `xray` 未声明未实现协议；当前不声明 `dokodemo-door`
- `xray` 传统 Shadowsocks inbound 使用多用户 `clients` 结构，避免只吃首个用户
- `trojan` inbound 在 `sing-box` / `xray` 下都会在缺省时补 TLS 兜底，减少面板下发 `tls=0` 时的启动兼容问题
- `grpc` 传输同时兼容 `service_name` 与 `serviceName` 两种字段命名
- 路由顺序在默认保护规则启用时为：内置保护规则 → structured custom routes → raw custom routes → panel routes → final outbound
