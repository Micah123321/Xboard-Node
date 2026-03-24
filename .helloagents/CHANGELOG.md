# CHANGELOG

## [Unreleased]

### 快速修复

- **[kernel]**: 为 `sing-box` 补充 `tuic + kernel.egress.shadowsocks` 最小回归测试。默认测试集新增配置生成断言，验证 `route.final` 指向 `default-shadowsocks`；`with_quic` 条件下新增运行态测试，验证 TUIC 启动后的默认出站仍为 `default-shadowsocks`。本次未修改运行逻辑，因为当前代码路径未复现默认出站回退到 `direct`。
  - 类型: 快速修复（测试补强，无运行逻辑改动）
  - 文件: internal/kernel/singbox/config_test.go, internal/kernel/singbox/tuic_with_quic_test.go

- **[service]**: 为 `sing-box + kernel.egress.shadowsocks` 增加本地 `debug_port` 调试能力，接口仅监听 `127.0.0.1`，返回 `default_outbound_tag`、SS 上游摘要和最近一次真实默认出站拨号结果；同时补充启动/重载日志与最小回归测试。
  - 类型: 快速修复（运行态可观测性增强）
  - 文件: cmd/xboard-node/main.go, cmd/xboard-node/main_test.go, internal/config/config.go, internal/config/config_test.go, internal/kernel/singbox/debug.go, internal/service/debug.go, internal/service/debug_test.go, internal/service/service.go, config.yml.example, README.md

## [0.0.4] - 2026-03-25

### 新增

- **[config]**: 新增最小 `hot-reload` 能力，配置文件变更后会在新配置合法时重启 service 实例，非法配置则保留旧实例继续运行。 — by yinjianm
  - 方案: [202603250316_minimal-hot-reload](archive/2026-03/202603250316_minimal-hot-reload/)

### 蹇€熶慨鏀?

- **[ci]**: 涓?`Build & Push Docker Image` 澧炲姞 GitHub Actions Buildx 灞傜紦瀛橈紝淇濈暀鐜版湁瑙﹀彂鏉′欢鍜?`linux/amd64,linux/arm64` 鍙屾灦鏋勯暅鍍忎骇鐗┿€?
  - 绫诲瀷: 蹇€熶慨鏀癸紙鏃犳柟妗堝寘锛?
  - 鏂囦欢: .github/workflows/ci.yml

### 快速修改

- **[ci]**: Docker 默认镜像构建平台调整为 `linux/amd64`，去掉默认 `arm64` 构建以缩短 CI 时长。
  - 类型: 快速修改（无方案包）
  - 文件: .github/workflows/ci.yml

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
