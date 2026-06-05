# 变更提案: alpine-openrc-installer

## 元信息
```yaml
类型: 修复
方案类型: implementation
优先级: P1
状态: 已确认
创建: 2026-06-05
```

---

## 1. 需求

### 背景
用户在 Alpine Linux 上执行远程 `install.sh` 原生安装命令时，脚本在 `ensure_systemd` 处因缺少 `systemd/systemctl` 直接失败。当前仓库 README 也把原生部署限制为 systemd 发行版，但用户明确要求支持 Alpine Linux 完成安装。

### 目标
让原生安装器在 Alpine Linux/OpenRC 环境下完成安装、升级、状态查询、默认出站管理和卸载等核心流程，同时保持 systemd 发行版现有行为不变。

### 约束条件
```yaml
时间约束: 本轮完成实现、验证、review、commit
性能约束: 不增加运行时常驻依赖
兼容性约束: systemd 路径保持原有 service 名称、文件路径和管理命令；Alpine 路径使用 OpenRC
业务约束: 不写入或提交用户暴露的真实 token；不连接远程服务器执行安装
```

### 验收标准
- [ ] `install.sh` 不再在 Alpine/OpenRC 下要求 `systemctl`，可生成 OpenRC init 脚本并通过 `rc-update`/`rc-service` 管理 `mi-node`。
- [ ] `install.sh status|upgrade|egress|uninstall` 在 OpenRC 环境下不调用 `systemctl`。
- [ ] `xbctl status|service|egress|upgrade|uninstall` 在 OpenRC 环境下具备对应服务管理能力。
- [ ] systemd 环境仍使用原有 `mi-node.service` 和 `systemctl` 行为。
- [ ] 脚本语法检查、Go 测试或等效验证通过。

---

## 2. 方案

### 技术方案
在 `install.sh` 中引入 init system 探测与服务管理封装，检测顺序为运行中的 systemd 优先，其次 OpenRC。保留 systemd unit 渲染逻辑，新增 OpenRC `/etc/init.d/mi-node` 渲染逻辑，并把 start/stop/enable/status/daemon-reload/log 提示等操作统一走封装函数。

在 `cmd/xbctl/main.go` 中增加 Go 侧 init system 探测和服务命令封装，使安装后的管理工具在 OpenRC 主机上不再硬编码 `systemctl` 与 `/etc/systemd/system/mi-node.service`。

### 影响范围
```yaml
涉及模块:
  - install.sh: 原生安装、升级、状态、默认出站、卸载的服务管理兼容
  - cmd/xbctl: 管理工具 service/status/upgrade/uninstall/egress 的 OpenRC 兼容
  - README.md: 原生部署适用环境和管理命令同步
预计变更文件: 4
```

### 风险评估
| 风险 | 等级 | 应对 |
|------|------|------|
| 服务管理抽象改动影响 systemd 原有路径 | 中 | 保留 systemd 优先探测，systemd 分支仍调用原命令；增加语法和测试验证 |
| OpenRC init 脚本参数或 pidfile 行为不兼容 | 中 | 使用 OpenRC `supervisor=supervise-daemon` 和 `command_args`，避免依赖后台化参数 |
| `xbctl` 与安装脚本服务路径不一致 | 中 | 两侧统一使用 `mi-node` OpenRC 服务名和 `/etc/init.d/mi-node` |
| 用户 token 泄露进入仓库 | 高 | 所有文档和方案只使用占位符，不记录真实 token |

### 方案取舍
```yaml
唯一方案理由: 失败点不只是入口检查，后续安装、升级、egress、卸载、xbctl 管理都依赖 systemctl；集中抽象服务管理可以一次性覆盖完整安装生命周期。
放弃的替代路径:
  - 仅删除 ensure_systemd 检查: 会在 install_staged_files/start_service 等后续 systemctl 调用继续失败。
  - 要求 Alpine 安装 systemd: 不符合 Alpine 默认 OpenRC 生态，也违背用户要求。
  - 单独维护 alpine-install.sh: 会造成安装逻辑分叉和长期漂移。
回滚边界: 可回退本次 `install.sh`、`cmd/xbctl/main.go`、README 和知识库变更；不涉及数据库或远程环境。
```

---

## 3. 核心场景

### 场景: Alpine 原生安装
**模块**: installer
**条件**: root 用户、Alpine/OpenRC 环境，存在 `openrc`、`rc-service`、`rc-update`
**行为**: 安装器渲染 `/etc/init.d/mi-node`，安装二进制和配置，启用并启动 `mi-node`
**结果**: 服务由 OpenRC 管理，后续可用 `rc-service mi-node status|restart|stop`

### 场景: systemd 原生安装
**模块**: installer
**条件**: systemd 正在运行
**行为**: 安装器渲染 `/etc/systemd/system/mi-node.service`，执行 `systemctl daemon-reload` 和 `systemctl enable --now`
**结果**: 既有 systemd 行为保持不变

### 场景: xbctl 服务管理
**模块**: xbctl
**条件**: 已安装 `xbctl`
**行为**: `xbctl service restart/status/logs` 按当前 init system 调用 systemd 或 OpenRC 命令
**结果**: Alpine 主机不会因缺少 `systemctl` 导致管理命令失败

---

## 4. 技术决策

### alpine-openrc-installer#D001: 使用 init system 抽象覆盖完整服务生命周期
**日期**: 2026-06-05
**状态**: ✅采纳
**背景**: Alpine 安装失败暴露出脚本和管理工具对 systemd 的全链路假设。
**选项分析**:
| 选项 | 优点 | 缺点 |
|------|------|------|
| A: 服务管理抽象 + OpenRC 分支 | 覆盖完整生命周期；systemd/OpenRC 行为集中维护 | 改动范围比单点修复更大 |
| B: 移除 systemd 检查并局部替换启动命令 | 改动少 | 后续流程仍会在 systemctl 调用失败 |
| C: 独立 Alpine 安装脚本 | 风险隔离 | 安装逻辑重复，后续功能容易不同步 |
**决策**: 选择方案 A
**理由**: 用户要求“Alpine Linux 系统完成”，必须覆盖安装完成后的管理链路，而不仅是跳过入口检查。
**影响**: `install.sh` 与 `xbctl` 的服务管理实现新增 OpenRC 分支。

---

## 5. 验证策略

```yaml
verifyMode: review-first
reviewerFocus:
  - install.sh 中 systemd/OpenRC 分支是否完整覆盖 install/status/upgrade/egress/uninstall
  - cmd/xbctl/main.go 是否仍保留 systemd 兼容，OpenRC 下不硬编码 systemctl
  - 是否有真实 token 或敏感信息进入文件
testerFocus:
  - bash -n install.sh
  - go test ./cmd/xbctl ./cmd/mi-node
  - go test ./internal/...
  - 代码搜索确认 OpenRC 分支覆盖关键 systemctl 调用点
uiValidation: none
riskBoundary:
  - 不连接用户服务器
  - 不执行生产部署、远程安装或真实服务启停
  - 不提交明文 token
```

---

## 6. 成果设计

N/A，非视觉任务。
