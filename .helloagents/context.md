# 项目上下文

## 基本信息

- 项目：mi-node
- 仓库路径：`E:\code\go\Xboard-Node`
- 主要语言：Go
- 当前关注点：完成仓内源码、产物、安装与运行命名从 `xboard-node` 到 `mi-node` 的全量切换

## 当前任务约束

- Go module path 已切换为 `github.com/micah123321/mi-node`
- 当前 GitHub 发布源仓库仍为 `Micah123321/Xboard-Node`，README / install.sh 保留该真实来源直到远端仓名改为 `mi-node`
- 编译产物、Docker 镜像、安装目录、systemd 服务名、容器名与 CI artifact 已统一为 `mi-node`
