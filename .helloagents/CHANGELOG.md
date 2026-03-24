# CHANGELOG

## [0.0.2] - 2026-03-25

### 新增

- **[config]**: 新增 `kernel.egress.shadowsocks`，支持传统 Shadowsocks 与 Shadowsocks 2022 默认出站。
  - 方案: [202603250215_add-egress-shadowsocks](plan/202603250215_add-egress-shadowsocks/)

### 修复

- **[kernel]**: `sing-box` / `xray` 默认出站构建逻辑现在可在 `socks5` 与 `shadowsocks` 之间按配置切换，并保持默认保护规则语义一致。
  - 方案: [202603250215_add-egress-shadowsocks](plan/202603250215_add-egress-shadowsocks/)
