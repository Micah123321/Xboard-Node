# 方案包：Shadowsocks 出站仅接受 URI

- 创建时间：2026-03-25 04:57
- 类型：implementation

## 1. 需求
### 背景

当前仓库已经支持 `kernel.egress.shadowsocks` 作为默认出站，但输入形式仍要求手动拆成 `address / port / method / password`。用户现在明确要求默认 SS 出站直接接受单个 `ss://...` URI，并且不再兼容旧拆分字段，避免安装脚本和本地配置继续出现“手拆 URI、字段拼错、运行时才发现配置错误”的问题。

### 目标

- `kernel.egress.shadowsocks` 只接受 `uri`
- 支持传统 Shadowsocks 和 SS2022 URI
- 配置加载阶段完成 URI 解析、合法性校验和派生字段回填
- `install.sh` 改为直接接收 `--egress-shadowsocks-uri`
- README 与 `config.yml.example` 改成 URI 用法

### 约束

- 不再兼容旧拆分字段输入
- 双内核现有默认 SS 出站生成逻辑保持不变，继续消费解析后的派生字段
- 继续保留传统 SS method 白名单与 SS2022 密钥校验
- 忽略 URI 中与当前默认出站无关的展示信息，例如 `#name` 和 `?type=tcp`

### 验收标准

- `config.Load()` 能加载传统 SS URI
- `config.Load()` 能加载 SS2022 URI
- 旧拆分字段写法会在加载配置时被拒绝
- 非法 URI、非法 method、非法 SS2022 key 会在加载配置时被拒绝
- `install.sh` 能写出 `kernel.egress.shadowsocks.uri`
- 定向测试通过，且 `sing-box` / `xray` 相关配置生成测试不回归

## 2. 方案

### 技术方案

- 在 `internal/config/egress.go` 将 `ShadowsocksEgressConfig` 调整为公开输入字段 `URI`
- 在配置校验阶段解析 `ss://...`，派生出 `Address / Port / Method / Password`
- 仅保留派生字段给内核配置生成使用，不再允许 YAML 直接写入拆分字段
- 在 `install.sh` 删除旧的 `--egress-shadowsocks` / `--egress-shadowsocks-method` / `--egress-shadowsocks-password` 输入路径，改成单个 `--egress-shadowsocks-uri`

### 影响范围

- 配置解析与校验：`internal/config`
- 安装脚本：`install.sh`
- 文档与示例：`README.md`、`config.yml.example`
- 定向测试：`internal/config/config_test.go`

### 风险

- 旧用户本地配置若仍使用拆分字段，升级后会在加载阶段直接失败；这是本次需求指定的行为，需要在文档中明确
- `ss://` URI 存在多种历史编码变体，需要对当前支持范围做清晰限制，避免“部分链接能用、部分链接静默错配”
- 若 URI 解析实现不严谨，可能把 method/password 拆错并传给双内核，导致运行时问题下沉
