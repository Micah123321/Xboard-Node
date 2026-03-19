# 任务清单: 中文文档与原生部署优化

> **状态:** 已完成（`bash -n install.sh` 因当前环境无可用 Bash / WSL 权限受限，未能执行）

目录: `helloagents/history/2026-03/202603200133_docs_cn_native_deploy/`

---

## 1. 安装部署文档
- [√] 1.1 在 `README.md` 中重写项目说明、安装步骤和部署建议，验证 why.md#需求-中文化项目文档-场景-新用户阅读-readme
- [√] 1.2 在 `config.yml.example` 中翻译注释并突出运行时内存调优项，验证 why.md#需求-提供本机一键部署方案-场景-小内存-linux-主机

## 2. 一键部署能力
- [√] 2.1 在 `install.sh` 中新增 `--gomemlimit` 与 `--gogc` 参数解析和校验，验证 why.md#需求-提供本机一键部署方案-场景-小内存-linux-主机
- [√] 2.2 在 `install.sh` 中将运行时配置写入节点配置文件，并更新帮助说明，验证 why.md#需求-提供本机一键部署方案-场景-小内存-linux-主机，依赖任务2.1

## 3. 安全检查
- [√] 3.1 执行安全检查（按G9: 输入验证、敏感信息处理、权限控制、EHRB风险规避）

## 4. 文档更新
- [√] 4.1 更新 `helloagents/wiki/modules/install.md`
- [√] 4.2 更新 `helloagents/CHANGELOG.md`

## 5. 测试
- [√] 5.1 执行 `go test ./...`
- [X] 5.2 执行 `bash -n install.sh`（失败原因: 当前环境缺少可用的 Bash，WSL 调用返回 `E_ACCESSDENIED`）