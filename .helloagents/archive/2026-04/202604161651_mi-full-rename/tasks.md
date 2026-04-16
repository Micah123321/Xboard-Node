# 任务清单: mi-node-full-rename

> **@status:** completed | 2026-04-16 17:05

```yaml
@feature: mi-node-full-rename
@created: 2026-04-16
@status: completed
@mode: R3
```

## 进度概览

| 完成 | 失败 | 跳过 | 总数 |
|------|------|------|------|
| 4 | 0 | 0 | 4 |

---

## 任务列表

### 1. 源码与模块标识

- [√] 1.1 将 `go.mod`、`cmd/xboard-node` 及所有内部 import path 全量切换为 `github.com/micah123321/mi-node` 与 `cmd/mi-node` | depends_on: []
- [√] 1.2 同步程序版本输出、启动日志和测试引用，确保源码层不再出现活动态 `xboard-node` 运行名 | depends_on: [1.1]

### 2. 构建与发布链

- [√] 2.1 修改 `Makefile`、`Dockerfile` 与 `.github/workflows/ci.yml`，统一编译产物、artifact、镜像运行名和 release 文件名为 `mi-node` | depends_on: [1.2]

### 3. 安装与运行时标识

- [√] 3.1 修改 `install.sh`、`config.yml.example`，统一安装目录、systemd 模板、容器名、镜像默认值和运维提示为 `mi-node`；当时有效发布源仍为旧仓名 | depends_on: [2.1]

### 4. 文档、知识库与验证

- [√] 4.1 同步 `README.md` 与 `.helloagents` 中受影响文档，回扫残留命名并执行测试/构建验证 | depends_on: [3.1]

---

## 执行日志

| 时间 | 任务 | 状态 | 备注 |
|------|------|------|------|
| 2026-04-16 16:51:00 | 方案包创建 | completed | 已创建 `202604161651_mi-full-rename` 目录与基础模板 |
| 2026-04-16 16:53:00 | 方案确认 | completed | 选择方案 A，全量硬切到 `mi` |
| 2026-04-16 17:00:00 | 目标修正 | completed | 按用户补充，将统一名称从 `mi` 修正为 `mi-node` |
| 2026-04-16 17:14:00 | 实现与验证 | completed | 已完成代码/脚本/文档改名，`go test ./...` 与当前平台构建、Linux amd64/arm64 交叉编译通过 |

---

## 执行备注

> 本轮当时保留有效发布源仓库 slug 为旧仓名，但仓内源码、产物、安装与运行命名全部切换到 `mi-node`，并将源码模块路径提前对齐到未来仓名 `github.com/micah123321/mi-node`。后续发布源已再切换到 `Micah123321/mi-node`。
