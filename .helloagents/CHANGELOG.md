# CHANGELOG

## [Unreleased]

## [0.0.5] - 2026-04-28

### 修复

- **[merge/deploy/config]**: 完整收口 `cedar2025/dev` 合并后的部署一致性问题：`cmd/mi-node` 接入 `RootConfig`/`instances`/machine mode，`install.sh` 收敛为 `mi-node.service` 原生安装器，`xbctl` 与 CI artifact 统一到 `mi-node`/`xbctl`，xray 协议声明补齐 `socks`/`http` 并移除错误文档声明，配置示例与 DNS/custom route 文档同步到代码事实。 — by yinjianm
  - 方案: [202604280026_fix-merge-deployment-consistency](archive/2026-04/202604280026_fix-merge-deployment-consistency/)
  - 决策: fix-merge-deployment-consistency#D001(以 mi-node 单轨承接 upstream 新能力)

### 快速修复

- **[repo/docs/kb]**: GitHub 发布源仓库已从旧仓名切换到 `Micah123321/mi-node`，`origin`、README Raw 地址、`install.sh` 默认发布源和 `.helloagents` 当前态路径说明已同步更新；本地工作目录已切换到 `E:\code\go\mi-node`。 — by yinjianm
  - 方案: [202604161713_repo-folder-rename-to-mi-node](archive/2026-04/202604161713_repo-folder-rename-to-mi-node/)
  - 决策: repo-folder-rename-to-mi-node#D001(立即同步本地目录与发布源到 mi-node)

- **[rename/build/install/docs]**: 仓内项目命名已从 `xboard-node` 全量切换到 `mi-node`；Go module path 现为 `github.com/micah123321/mi-node`，入口目录改为 `cmd/mi-node`，编译产物、Docker 镜像、安装目录、systemd 服务名、容器名与 CI artifact 全部同步为 `mi-node`。GitHub 发布源仓库现已切换到 `Micah123321/mi-node`，README 与 install 默认来源已同步收口。 — by yinjianm
  - 方案: [202604161651_mi-full-rename](archive/2026-04/202604161651_mi-full-rename/)
  - 决策: mi-full-rename#D001(仓内标识全量硬切为 mi-node)

- **[install/docs]**: `install.sh` 现在会明确区分 ACME HTTP-01 的公网 `80` 校验与 `--cert-http-port` 的本地监听语义；当使用自定义本地监听端口时，部署结果与证书排障输出会明确提示“公网 80 仍需转发到该端口”。 — by yinjianm
  - 方案: [202604152142_install-http01-preflight](archive/2026-04/202604152142_install-http01-preflight/)
  - 决策: install-http01-preflight#D001(不伪造任意公网端口 HTTP-01，改为增强预检与提示)

- **[install]**: `install.sh` 在 `singbox + --egress-shadowsocks-uri` 场景下新增启动后默认出站健康检查；若日志出现 `shadowsocks egress probe failed`，部署会直接判失败、输出排查命令，并保留节点配置与服务现场。 — by yinjianm
  - 类型: 快速修复（安装阶段 SS 默认出站失败收口）
  - 文件: install.sh, README.md

- **[config/install]**: kernel.egress.shadowsocks 改为仅接受 ss://... URI 输入，配置加载阶段会完成传统 SS / SS2022 URI 解析、method 白名单校验和 SS2022 密钥校验；install.sh 同步切换为 --egress-shadowsocks-uri，README 与 config.yml.example 全部改用 URI 示例。
  - 类型: 快速修复（URI-only 出站输入收敛）
  - 文件: internal/config/egress.go, internal/config/config_test.go, install.sh, README.md, config.yml.example

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
