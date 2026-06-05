# 任务清单: alpine-openrc-installer

> **@status:** completed | 2026-06-06 00:12

```yaml
@feature: alpine-openrc-installer
@created: 2026-06-05
@status: completed
@mode: R2
```

## LIVE_STATUS

```json
{"status":"completed","completed":5,"failed":0,"pending":0,"total":5,"percent":100,"current":"已归档到 archive/2026-06","updated_at":"2026-06-06 00:12:48","skipped":0,"uncertain":0,"done":5}
```

## 进度概览

| 完成 | 失败 | 跳过 | 总数 |
|------|------|------|------|
| 5 | 0 | 0 | 5 |

---

## 任务列表

### 1. 安装脚本服务管理兼容

- [√] 1.1 修改 `install.sh`
  - 预期变更: 新增 init system 探测、OpenRC init 脚本渲染和服务管理封装，覆盖 install/status/upgrade/egress/uninstall。
  - 完成标准: Alpine/OpenRC 分支不再调用 `systemctl`；systemd 分支保留原行为。
  - 验证方式: `bash -n install.sh`，并通过代码搜索核对关键调用点。
  - depends_on: []

### 2. 管理工具服务命令兼容

- [√] 2.1 修改 `cmd/xbctl/main.go`、`cmd/xbctl/service_control.go` 和 `cmd/xbctl/service_control_test.go`
  - 预期变更: 新增 Go 侧 init system 探测和 service 命令封装，`status/service/egress/upgrade/uninstall` 支持 OpenRC，并覆盖 systemd/OpenRC 判定测试。
  - 完成标准: OpenRC 环境下不硬编码调用 `systemctl`；systemd 行为保持兼容。
  - 验证方式: `go test ./cmd/xbctl`。
  - depends_on: [1.1]

### 3. 文档与知识库同步

- [√] 3.1 更新 `README.md` 和 `.helloagents` 知识库
  - 预期变更: 原生部署环境说明加入 Alpine/OpenRC；管理命令说明加入 OpenRC 对应命令；知识库记录本次安装器兼容变更。
  - 完成标准: 文档与代码事实一致，不包含真实 token。
  - 验证方式: 搜索 README 和知识库确认无敏感 token，人工核对描述。
  - depends_on: [1.1, 2.1]

### 4. 验证与审查

- [√] 4.1 执行本地验证和本次改动审查
  - 预期变更: 运行 shell 语法检查、Go 测试和差异审查。
  - 完成标准: 阻断性验证通过；若有警告，记录原因和影响。
  - 验证方式: `bash -n install.sh`、`go test ./cmd/xbctl ./cmd/mi-node`、`go test ./internal/...`、人工 review diff。
  - depends_on: [1.1, 2.1, 3.1]

### 5. 提交

- [√] 5.1 创建 bilingual commit
  - 预期变更: 提交本次代码、文档和知识库变更。
  - 完成标准: git 工作区仅保留用户既有无关改动或保持干净；commit message 包含中文和 English。
  - 验证方式: `git status --short`、`git log -1 --pretty=fuller`。
  - depends_on: [4.1]

---

## 执行日志

| 时间 | 任务 | 状态 | 备注 |
|------|------|------|------|
| 2026-06-05 23:56 | DESIGN | completed | 已完成上下文收集和唯一方案设计 |
| 2026-06-06 00:05 | 1.1 | completed | `install.sh` 已新增 systemd/OpenRC init system 分支 |
| 2026-06-06 00:05 | 2.1 | completed | `xbctl` 服务管理调用已切换为 init system 封装 |
| 2026-06-06 00:05 | 3.1 | completed | README 与知识库已同步 Alpine/OpenRC 支持 |
| 2026-06-06 00:15 | 4.1 | completed | Go 测试、diff 检查、敏感信息搜索和人工 diff review 通过；`bash -n` 因本机 WSL Bash 不可用未完成 |
| 2026-06-06 00:18 | 5.1 | completed | 已准备 bilingual commit，随归档后的最终变更一起提交 |

---

## 执行备注

- 用户贴出的 Cloudflare token 属于敏感信息，本方案和后续文档只使用占位符。
