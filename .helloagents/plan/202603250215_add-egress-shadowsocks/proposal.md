# 方案包：新增 kernel.egress.shadowsocks

- 创建时间：2026-03-25 02:15
- 类型：implementation

## 1. 需求

### 背景

当前项目的默认出站只支持 `kernel.egress.socks5`。用户希望接入部分只能通过 Shadowsocks 落地的节点，并要求配置体验、默认路由语义与现有 SOCKS5 方案保持一致。

### 目标

- 新增 `kernel.egress.shadowsocks`
- 同时支持传统 Shadowsocks 与 Shadowsocks 2022
- 保持 `sing-box` / `xray` 双内核一致行为
- 默认出站仍由 `kernel.egress.DefaultOutboundTag()` 控制

### 约束

- 不改变现有 `socks5` 配置行为
- 同一时刻仅允许一种默认上游出站方案生效
- 需要对 `2022-blake3-*` 的密码格式做启动前校验

### 验收标准

- `config.Load()` 能正确解析并校验 `egress.shadowsocks`
- `sing-box` / `xray` 均能生成对应默认 Shadowsocks 出站配置
- 传统 SS 与 SS2022 均有单元测试覆盖
- README / 示例配置同步更新

## 2. 方案

### 技术方案

- 在 `internal/config/egress.go` 增加 `ShadowsocksEgressConfig`
- 为 `EgressConfig` 增加 Shadowsocks 启用判断、默认 tag 选择与配置互斥校验
- 在 `internal/kernel/singbox/config.go` / `internal/kernel/xray/config.go` 各补一个默认 Shadowsocks outbound builder
- 对 `2022-blake3-*` 出站密码支持单 key 与 `<server_key>:<user_key>` 组合格式

### 影响范围

- 配置解析：`internal/config`
- 内核配置生成：`internal/kernel/singbox`、`internal/kernel/xray`
- 文档示例：`README.md`、`config.yml.example`
- 测试：`internal/config`、`internal/kernel/singbox`、`internal/kernel/xray`

### 风险

- Xray 与 sing-box 对 SS2022 出站密码格式的要求需保持一致
- 默认出站 tag 选择逻辑改动后，不能影响现有 SOCKS5 路径
