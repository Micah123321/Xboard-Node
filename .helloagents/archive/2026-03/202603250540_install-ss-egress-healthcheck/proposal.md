# 方案包：安装脚本 SS 出站健康检查

- 创建时间：2026-03-25 05:40
- 类型：implementation

## 1. 需求
### 背景

当前 `install.sh` 在配置 `--egress-shadowsocks-uri` 后，会正常写入配置并启动节点，但部署结果只基于“服务是否启动”和“证书是否生成”收口。对 `sing-box + kernel.egress.shadowsocks` 来说，节点内核已经内置默认出站真实 probe；一旦上游 SS/SS2022 不可达，运行日志会很快出现 `shadowsocks egress probe failed`，但安装脚本仍然打印“节点部署完成”，容易把明显失败的默认出站误判成成功部署。

### 目标

- 在 `install.sh` 中为 `--egress-shadowsocks-uri` 增加启动后健康检查
- 对 `singbox` 内核等待并解析默认 SS 出站 probe 结果
- 若 probe 明确失败，部署直接判失败并返回非零退出码
- 失败时保留节点配置与服务实例，同时输出最短排查命令
- 文档补充该行为边界，说明当前健康检查只覆盖 `sing-box` 的真实 probe

### 约束

- 不回退或删除已部署节点，避免把失败现场直接抹掉
- 不改动内核 probe 逻辑，只复用现有启动日志信号
- 不扩大到 `xray` 运行态探测；该内核当前没有等价 probe
- 尽量不碰用户现有 README 未提交改动，只做最小文档增量

### 验收标准

- `install.sh` 在 `singbox + --egress-shadowsocks-uri` 场景下会等待 probe 结果
- 观察到 `shadowsocks egress probe failed` 时，脚本输出失败摘要和排查命令，并以非零状态退出
- 观察到 `shadowsocks egress probe succeeded` 时，脚本保持现有成功摘要
- `xray` 或无 SS egress 的场景不被错误阻断
- 至少完成 Bash 语法检查和定向行为验证

## 2. 方案

### 技术方案

- 在 `install.sh` 中新增 SS egress 健康检查等待逻辑，复用服务启动后的日志结果作为判断来源
- 启动节点前记录时间锚点；节点启动后轮询 `journalctl` 或 `docker logs` 中的 probe 日志
- 将 probe 结果收敛为三态：`success` / `failed` / `timeout`
- 对 `success` 继续现有部署完成流程；对 `failed` 立即输出失败摘要、排查命令和保留现场说明，并退出 1；对 `timeout` 输出警告但不把它伪装成 probe 成功
- 在 `README.md` 增量说明：`install.sh` 在 `sing-box + --egress-shadowsocks-uri` 下会等待默认出站 probe，失败会直接判部署失败

### 影响范围

- 安装流程与部署收口：`install.sh`
- 使用说明：`README.md`
- 方案记录与变更沉淀：`.helloagents/plan/*`、`.helloagents/CHANGELOG.md`

### 风险

- 仅依赖日志匹配时，若服务未输出 probe 日志可能出现超时不确定状态 | 中 | 使用时间锚点 + 成功/失败关键词精确匹配，并在超时时明确标注“未拿到结果”
- Docker / systemd 两种部署通道的日志读取接口不同 | 中 | 分通道实现读取函数，保留各自排查命令
- 用户本地 `README.md` 已有未提交修改，直接覆盖存在冲突风险 | 低 | 仅做最小增量 patch，不重写现有段落

