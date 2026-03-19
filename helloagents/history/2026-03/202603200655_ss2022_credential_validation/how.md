# 实施方案: SS2022 凭证前置校验

## 方案概述
在 `internal/kernel` 提供公共的 SS2022 凭证校验辅助函数，按 cipher 推导期望密钥长度，并在 `sing-box`、`xray` 的启动、重载和用户更新路径统一调用。这样可以在生成或应用底层配置前直接返回可读错误。

## 实施步骤
1. 在 `internal/kernel` 新增公共校验函数。
2. 在 `sing-box` 的 `Start`、`Reload`、`reloadInboundsLocked` 中调用校验。
3. 在 `xray` 的 `Start`、`AddUsers`、`UpdateUsers` 中调用校验，避免跳过非法用户后仍更新内部状态。
4. 调整现有 SS2022 测试数据为合法 base64 示例，并新增校验测试。
5. 更新知识库与变更记录，执行相关测试。

## 关键决策
- 只对 `shadowsocks` 的 `2022-blake3-*` cipher 启用校验，不影响传统 SS 或其他协议。
- 错误信息包含字段名和用户 ID，便于直接对应面板数据。
- 用户热更新失败时整体拒绝本次变更，避免内核实际用户集合与内存状态不一致。

## 验证策略
- 单元测试覆盖:
  - 合法 `server_key` + 合法用户密码
  - 非法 `server_key`
  - 非法用户密码
  - 不同 cipher 的长度要求
- 执行 `go test` 覆盖 `internal/kernel/...`
