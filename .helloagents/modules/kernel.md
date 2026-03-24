# kernel 模块

## 职责

- 生成 `sing-box` 与 `xray` 的运行时配置
- 将面板配置和本地 `kernel.egress` 配置转换为内核原生 outbound / route

## 当前关键行为

- 默认出站仍保留 `direct` / `block` 基础结构
- 当配置 `kernel.egress.shadowsocks` 时，会生成 `default-shadowsocks` outbound
- `sing-box` 与 `xray` 对默认 Shadowsocks 出站保持一致的 tag 与路由语义
