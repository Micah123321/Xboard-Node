# traffic-limit 模块

## 职责

- 解析面板下发的节点级 `traffic_limit` 配置
- 基于 tracker tick 的上行 / 下行增量累计当前周期用量
- 达到额度后停止内核，并在重置时间到达或面板手动重置后恢复运行
- 将限额状态持久化到本地 JSON，并通过 metrics 上报给 Xboard

## 当前关键行为

- 面板协议在 `panel.NodeConfig` 和 `model.NodeSpec` 中使用 `TrafficLimit` / `TrafficLimitSpec` 承载配置，machine mailbox clone 不会丢失该字段
- `internal/trafficlimit.Manager` 持有启用状态、额度、重置日、重置时间、时区、周期用量、下次重置和 suspended 状态
- 状态文件固定写入 `kernel.config_dir/traffic-limit-state.json`；进程重启后会恢复周期用量和 suspended 状态
- `ResetDay` 支持 `1-31`，短月按当月最后一天计算；非法时区回退 UTC
- `tracker.Process()` 返回本 tick 的节点总上行 / 下行增量，`Service.trackAndEnforce()` 把两者合并交给限额管理器
- 达到额度后 `Service` 调用 `kernel.Stop()`，并通过 `startKernel()` 与 `ensureRunning()` 的 `CanRun()` gate 阻止自动重启
- 处于限额下线期间，用户全量更新和增量更新仍会刷新 `lastUsers` 与限速器状态，但不会调用内核用户 API；重置恢复时使用最新缓存用户启动
- 到达 `next_reset_at` 或面板下发更新的 `last_reset_at` 后，限额状态恢复 normal，`Service` 在已有 `lastConfig` 和 `lastUsers` 时尝试重新启动内核
- metrics 中追加 `traffic_limit`，包含 `enabled / limit / used / suspended / last_reset_at / next_reset_at / suspended_at / status`

## 依赖关系

- 依赖 `internal/tracker` 计算每个 tick 的双向增量
- 依赖 `internal/service` 执行内核停启 gate、配置热更新、用户缓存和 metrics 上报
- 依赖 `internal/panel`、`internal/model` 与 `internal/controlplane` 传递面板配置
- 依赖 Xboard `ServerTrafficLimitService` 下发配置、处理面板侧手动/定时重置和状态回写
