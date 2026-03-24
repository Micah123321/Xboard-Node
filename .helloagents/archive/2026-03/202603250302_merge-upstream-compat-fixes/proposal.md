# 方案包：选择性合并上游协议兼容性修复

- 创建时间：2026-03-25 03:02
- 类型：implementation

## 1. 需求

### 背景

当前本地 `dev` 分支相对 `cedar2025/Xboard-Node:dev` 处于 `ahead 15 / behind 8`。用户要求保留本地已有全部改动，同时评估上游落后的 8 个提交中哪些是确实值得保留的功能，并将这些高价值改动合并进来。

### 目标

- 保留本地当前分支的所有有效改动
- 选择性吸收上游 `dev` 中确实有价值的协议兼容性修复
- 不将不必要的大范围重构强行带入本次合并
- 若出现冲突，先明确冲突点与取舍，再由用户拍板

### 约束

- 本次以本地分支为主线，不做全量追平上游
- 优先吸收与 `Shadowsocks` / `SS2022` / `Trojan` / `xray` 兼容性直接相关的修复
- 暂不直接合入上游 `nlog`、配置热重载、service/tracker 并发模型重构
- 合并后必须完成最小回归验证，确保不破坏本地新加的 `egress.shadowsocks` 能力

### 验收标准

- 上游 8 个提交已完成价值判断，并有明确保留/暂缓结论
- 协议兼容性相关上游修复已在本地分支落地
- 冲突文件与取舍点已清晰记录；需要用户拍板的部分在执行前单独停顿确认
- 合并后相关测试通过，且本地已有 `Shadowsocks egress` 改动仍可工作

## 2. 方案

### 技术方案

- 以本地 `dev` 为主线，选择性吸收上游以下提交的有效变更：
  - `aaad2ba` `fix: fix Shadowsocks 2022 compatibility`
  - `bfc24c3` `fix: fix Trojan compatibility`
  - `4f1f41a` `fix: fix Trojan compatibility in xray kernel`
  - `4676caa` `fix: fix Shadowsocks support for Xray kernel`
- 对上述提交不做盲目 `cherry-pick`，而是先比对命中代码，再按本地现状手工合并需要的逻辑
- 对 `README.md`、`.gitignore` 这类非核心冲突文件，仅在需要时做最小整合
- 暂不引入以下上游大改：
  - `7e3ad7c` `feat: nlog, config hot-reload, and concurrency fixes`
  - `3f1234a` `refactor: rework limiter, traffic accounting, and logging (nlog)`
  - `e8e2abb` `perf: optimize throughput and scheduler efficency`

### 影响范围

- 协议配置生成：`internal/kernel/singbox/config.go`、`internal/kernel/xray/config.go`
- 运行时兼容：`internal/kernel/xray/xray.go`
- 对应测试：`internal/kernel/singbox/config_test.go`、`internal/kernel/xray/config_test.go`
- 可能的小范围文档/忽略规则整合：`README.md`、`.gitignore`

### 风险

- `internal/kernel/singbox/config.go` 同时承载本地默认 egress 规则语义与上游协议兼容修复，手工合并时容易误覆盖
- `internal/kernel/xray/config.go` 的传统 SS / SS2022 用户结构若整合不完整，会出现“配置能加载但生成的 Xray inbound/outbound 仍不兼容”的风险
- 若误把上游 `service` / `tracker` / `nlog` 改造带进来，范围会明显超出本轮需求
