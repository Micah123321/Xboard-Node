# 任务清单: SS2022 凭证前置校验

> **状态:** 已完成（`go test ./internal/kernel/...` 使用仓库内临时 `GOCACHE` 执行通过）

目录: `helloagents/history/2026-03/202603200655_ss2022_credential_validation/`

---

## 1. 公共校验
- [√] 1.1 新增 `shadowsocks` 2022 凭证校验辅助函数
- [√] 1.2 为 `server_key` 和用户密码提供明确错误信息

## 2. 内核接入
- [√] 2.1 在 `sing-box` 启动/重载/用户热更新前接入校验
- [√] 2.2 在 `xray` 启动/用户热更新前接入校验

## 3. 测试
- [√] 3.1 调整现有 SS2022 测试数据为合法 base64 示例
- [√] 3.2 新增校验单元测试
- [√] 3.3 执行 `go test ./internal/kernel/...`

## 4. 文档同步
- [√] 4.1 更新 `helloagents/wiki/modules/kernel.md`
- [√] 4.2 更新 `helloagents/CHANGELOG.md`
- [√] 4.3 迁移方案包并更新 `helloagents/history/index.md`
