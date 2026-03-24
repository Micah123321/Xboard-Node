# CHANGELOG

## [0.0.4] - 2026-03-25

### 新增

- **[config]**: 新增最小 `hot-reload` 能力，配置文件变更后会在新配置合法时重启 service 实例，非法配置则保留旧实例继续运行。 — by yinjianm
  - 方案: [202603250316_minimal-hot-reload](archive/2026-03/202603250316_minimal-hot-reload/)

## [0.0.3] - 2026-03-25

### 修复

- **[kernel]**: 选择性吸收上游 `Shadowsocks` / `Trojan` 协议兼容性修复，补齐 `xray` 传统 Shadowsocks 多用户结构、`singbox/xray` Trojan TLS 兜底，以及 `grpc serviceName` 兼容。 — by yinjianm
  - 方案: [202603250302_merge-upstream-compat-fixes](archive/2026-03/202603250302_merge-upstream-compat-fixes/)

## [0.0.2] - 2026-03-25

### 新增

- **[config]**: 新增 `kernel.egress.shadowsocks`，支持传统 Shadowsocks 与 Shadowsocks 2022 默认出站。
  - 方案: [202603250215_add-egress-shadowsocks](plan/202603250215_add-egress-shadowsocks/)

### 修复

- **[kernel]**: `sing-box` / `xray` 默认出站构建逻辑现在可在 `socks5` 与 `shadowsocks` 之间按配置切换，并保持默认保护规则语义一致。
  - 方案: [202603250215_add-egress-shadowsocks](plan/202603250215_add-egress-shadowsocks/)

### 快速修改

- **[install]**: `install.sh` 新增 `--egress-shadowsocks`、`--egress-shadowsocks-method`、`--egress-shadowsocks-password`，并补充 `xray + aes-192-gcm` 拦截提示。
  - 类型: 快速修改（无方案包）
  - 文件: install.sh, README.md
- **[config]**: 补充 `kernel.egress.shadowsocks` method 白名单校验，并在 `xray + aes-192-gcm` 组合上于加载配置阶段直接拒绝。
  - 类型: 快速修改（无方案包）
  - 文件: internal/config/egress.go, internal/config/config.go, internal/config/config_test.go, install.sh
