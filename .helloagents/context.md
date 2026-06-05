# 项目上下文

## 基本信息

- 项目：mi-node
- 仓库路径：`E:\code\go\mi-node`
- 主要语言：Go
- 当前关注点：mi-node 作为 Xboard 节点端，负责协议运行、默认出站、墙检测执行，以及节点级月流量限额的本地强制下线与重置恢复

## 当前任务约束

- Go module path 已切换为 `github.com/micah123321/mi-node`
- 当前 GitHub 发布源仓库已切换为 `Micah123321/mi-node`，README / install.sh 默认来源与其保持一致
- 编译产物、Docker 镜像、安装目录、服务名、容器名与 CI artifact 已统一为 `mi-node`
- 当前原生安装路径为单服务：systemd 使用 `mi-node.service`，Alpine/OpenRC 使用 `mi-node`；主配置 `/etc/mi-node/config.yml` 使用 RootConfig/`instances:`；`xbctl` 管理同一套 `/etc/mi-node` 配置与凭据
- 面板下发 `traffic_limit` 时，节点端会把周期用量和 suspended 状态写入 `kernel.config_dir/traffic-limit-state.json`；超额后停止内核并阻止自动重启，重置时间到达或面板手动重置后恢复运行
