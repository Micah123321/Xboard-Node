# 变更提案: egress management

## 元信息
```yaml
类型: 新功能/修复
方案类型: implementation
优先级: P1
状态: 采纳
创建: 2026-04-28
```

---

## 1. 需求

### 背景
新版部署已统一到 `mi-node.service` + `/etc/mi-node/config.yml` 的 `instances:`。迁移旧 `Xboard-Node` 后，用户需要给某个已存在节点快速添加、切换或清除默认落地出站；当前只能重新安装或手改 YAML，容易丢配置，也不方便把 node `322` 这种已迁移节点补回 SOCKS5 落地。

### 目标
- 新增 `xbctl egress list/set/clear`，可按 `--node-id`、`--instance-id` 或必要时按 `--panel-url + --node-id` 定位已存在实例。
- 支持 SOCKS5、传统 Shadowsocks、SS2022，配置写入实例级 `kernel.egress`。
- 新增 `install.sh egress ...` 远程一键入口，方便继续用 `bash <(curl ...)` 操作已部署机器。
- 默认修改后重启 `mi-node.service`，并支持 `--no-restart` 跳过重启。
- 同步修复迁移脚本落地配置继承，避免后续迁移再次丢失 `kernel.egress.*`。

### 约束条件
```yaml
兼容性约束: 不破坏现有 install/update/uninstall/list/remove 行为；保留旧部署和 legacy 单节点配置读取能力
安全约束: 命令输出不得打印 SOCKS5/SS 密码；配置文件仍按现有权限写入
业务约束: 只管理默认出站 kernel.egress，不改面板节点协议或用户配置
运行约束: 远程入口只能依赖 bash/systemctl/已安装或可下载的 xbctl
```

### 验收标准
- [ ] `xbctl egress set --node-id 322 --socks5-url ...` 能更新对应实例，并写入 SOCKS5 地址、端口、用户名、密码和默认规则开关
- [ ] `xbctl egress set --node-id 322 --shadowsocks-uri ss://...` 能写入传统 SS 或 SS2022 URI，并清除旧 SOCKS5
- [ ] `xbctl egress clear --node-id 322` 能清除该实例默认上游出站
- [ ] `xbctl egress list` 能列出各实例当前出站类型，且不泄露密码
- [ ] `install.sh egress ...` 能远程调用同等能力，支持 `--no-restart`
- [ ] 迁移脚本能同步旧配置中的 `kernel.egress.socks5` / `kernel.egress.shadowsocks.uri`
- [ ] Go 测试、shell 语法检查、构建验证通过

---

## 2. 方案

### 技术方案
在 `cmd/xbctl/main.go` 中实现 egress 子命令，复用现有 `loadWritableRootConfig`、`normalizeRootInstances`、`writeRootConfig`、`writeInstallMeta` 与 `systemctl restart` 路径。新增解析器把 SOCKS5 URL 拆成结构化 `config.SOCKS5EgressConfig`，SS/SS2022 保持 `ss://...` URI 原样交给 `internal/config` 的现有校验逻辑。

`install.sh` 新增 `egress` action。远程脚本只负责下载/准备 `xbctl` 并透传参数给 `xbctl egress`，避免重复实现 YAML 修改逻辑。

迁移脚本补齐 `kernel.egress` 读取：结构化 SOCKS5 和 `socks5://...` 两种旧写法都转换成安装器参数；`kernel.egress.shadowsocks.uri` 原样传入。

### 影响范围
```yaml
涉及模块:
  - cmd/xbctl: 新增 egress 管理命令与测试
  - install.sh: 新增远程 egress action
  - scripts/migrate-to-mi-node.sh: 同步迁移 kernel.egress
  - README.md/MIGRATE.md/config.yml.example: 更新使用说明
  - .helloagents: 同步知识库和变更记录
预计变更文件: 8-10
```

### 风险评估
| 风险 | 等级 | 应对 |
|------|------|------|
| 错误定位实例导致改错节点 | 中 | 要求定位结果唯一；多实例无唯一匹配时报错 |
| 密码泄露到命令输出或日志 | 中 | list/log 只显示地址和认证标记，不输出 secret |
| 生成非法 egress 导致服务启动失败 | 中 | 复用 `config.LoadRoot` 校验写出的配置；测试覆盖 SOCKS5 与 SS URI |
| 远程入口与本地工具参数不一致 | 低 | `install.sh egress` 只透传给 `xbctl egress` |

### 方案取舍
```yaml
唯一方案理由: 以 xbctl 作为唯一写配置入口，install.sh 只做远程分发和透传，能避免 shell 与 Go 双份 YAML 修改逻辑漂移。
放弃的替代路径:
  - 只在 install.sh 中实现: 需要 shell 手写 YAML 合并，容易再次覆盖 instances
  - 只修迁移脚本: 不能满足后续切换落地和补救已部署节点的管理需求
  - 手工文档指导修改 config.yml: 对多节点 instances 风险高，无法一键验证和重启
回滚边界: 可回退本次 xbctl/install.sh/migrate 文档变更；已写入的用户配置可用 xbctl egress clear 或备份恢复。
```

---

## 3. 技术设计

### CLI 设计
```bash
xbctl egress list [--output text|json]
xbctl egress set --node-id 322 --socks5-url 'socks5://user:pass@host:port' [--no-restart]
xbctl egress set --node-id 322 --socks5 host:port --socks5-user USER --socks5-pass PASS [--no-restart]
xbctl egress set --node-id 322 --shadowsocks-uri 'ss://...' [--no-restart]
xbctl egress clear --node-id 322 [--no-restart]

bash install.sh egress --node-id 322 --socks5-url 'socks5://...'
bash install.sh egress --node-id 322 --shadowsocks-uri 'ss://...'
bash install.sh egress clear --node-id 322
```

### 数据模型
不新增配置模型，继续使用：

| 字段 | 类型 | 说明 |
|------|------|------|
| `kernel.egress.enable_default_rules` | `*bool` | 设置落地时写为 `true` |
| `kernel.egress.prefer_ipv4` | `*bool` | 设置落地时写为 `true` |
| `kernel.egress.socks5` | `SOCKS5EgressConfig` | SOCKS5 默认出站 |
| `kernel.egress.shadowsocks.uri` | `string` | 传统 SS / SS2022 默认出站 |

---

## 4. 核心场景

### 场景: 给已迁移节点补 SOCKS5 落地
**模块**: `cmd/xbctl`, `install.sh`
**条件**: `/etc/mi-node/config.yml` 中已有 node `322` 实例
**行为**: 执行 `install.sh egress --node-id 322 --socks5-url 'socks5://...'`
**结果**: 只更新 node `322` 的实例级 `kernel.egress`，并重启 `mi-node.service`

### 场景: 从 SOCKS5 切换到 SS2022
**模块**: `cmd/xbctl`
**条件**: 节点已有 SOCKS5 出站
**行为**: 执行 `xbctl egress set --node-id 322 --shadowsocks-uri 'ss://...'`
**结果**: 清除 SOCKS5，写入 Shadowsocks URI，保持互斥配置

---

## 5. 技术决策

### egress management#D001: 以 xbctl 作为唯一配置修改入口
**日期**: 2026-04-28
**状态**: ✅采纳
**背景**: 多节点 `instances:` 合并必须避免 shell 手写 YAML 覆盖其他实例。
**选项分析**:
| 选项 | 优点 | 缺点 |
|------|------|------|
| A: xbctl 管理配置，install.sh 透传 | 配置逻辑集中，可测试，复用现有 RootConfig 写回 | 需要先确保 xbctl 可用 |
| B: install.sh 直接改 YAML | 远程脚本自包含 | shell 解析 YAML 风险高，容易覆盖实例 |
| C: 只提供文档手改 | 实现最少 | 不满足一键管理，也无法防止误改 |
**决策**: 选择方案 A
**理由**: 当前项目已经将安装配置生成收敛到 `xbctl config init`，继续让 `xbctl` 承担 egress 写回能保持单一事实来源。
**影响**: `install.sh egress` 必须准备或复用 `xbctl`，并把参数交给 `xbctl egress`。

---

## 6. 验证策略

```yaml
verifyMode: test-first
reviewerFocus:
  - cmd/xbctl/main.go 的实例定位和密码脱敏输出
  - install.sh egress 参数透传是否破坏 install/update
  - migrate-to-mi-node.sh 对旧配置 egress 的解析边界
testerFocus:
  - go test ./cmd/xbctl ./internal/config
  - go test ./...
  - go build ./cmd/mi-node
  - go build ./cmd/xbctl
  - bash -n install.sh
  - bash -n scripts/migrate-to-mi-node.sh
  - xbctl egress set/list/clear 的临时配置单测
uiValidation: none
riskBoundary:
  - 不执行生产服务器 systemctl 操作
  - 不在输出中打印用户提供的 SOCKS5/SS 密码
```

---

## 7. 成果设计

N/A，非视觉任务。
