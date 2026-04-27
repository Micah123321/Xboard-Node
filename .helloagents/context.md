# 项目上下文

## 基本信息

- 项目：mi-node
- 仓库路径：`E:\code\go\mi-node`
- 主要语言：Go
- 当前关注点：完成仓内源码、产物、安装与运行命名从 `xboard-node` 到 `mi-node` 的全量切换

## 当前任务约束

- Go module path 已切换为 `github.com/micah123321/mi-node`
- 当前 GitHub 发布源仓库已切换为 `Micah123321/mi-node`，README / install.sh 默认来源与其保持一致
- 编译产物、Docker 镜像、安装目录、systemd 服务名、容器名与 CI artifact 已统一为 `mi-node`
- 当前原生安装路径为单服务 `mi-node.service`，主配置 `/etc/mi-node/config.yml` 使用 RootConfig/`instances:`；`xbctl` 管理同一套 `/etc/mi-node` 配置与凭据
