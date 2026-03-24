# 变更提案: fix-tuic-singbox-shadowsocks-egress

## 元信息
```yaml
类型: 修复
方案类型: implementation
优先级: P1
状态: 草稿
创建: 2026-03-25
```

---

## 1. 需求

### 背景
当前项目已经支持 `kernel.egress.shadowsocks`，配置层、`install.sh`、`sing-box/xray` 配置生成和静态测试都已补齐。但在线上 `tuic + sing-box + egress.shadowsocks` 场景中，节点运行日志仍持续出现 `using outbound/direct[direct]`，与预期默认经 `default-shadowsocks` 出站不一致。

### 目标
修复 `sing-box` 内核在 `tuic + egress.shadowsocks` 场景下默认 SS 出站未生效的问题，并补充最小回归测试，确保该组合后续不会回退到 `direct`。

### 约束条件
```yaml
时间约束: 当前回合内完成最小可验证修复
性能约束: 不引入额外常驻开销，不扩大默认路由规则范围
兼容性约束: 不修改 xray 行为，不改变已有 socks5 egress 语义
业务约束: 仅修 sing-box 的 tuic + egress.shadowsocks 运行态问题
```

### 验收标准
- [ ] `sing-box` 在 `tuic + egress.shadowsocks` 组合下生成的运行配置默认出站明确指向 `default-shadowsocks`
- [ ] 新增最小回归测试，覆盖 `tuic + egress.shadowsocks` 组合
- [ ] 不影响现有 `shadowsocks` 入站、`socks5` 出站和 xray 相关测试

---

## 2. 方案

### 技术方案
聚焦 `internal/kernel/singbox` 的配置生成与相关运行态路径，先补一个专门针对 `tuic + egress.shadowsocks` 的失败用例，再根据失败位置修正 sing-box 端默认出站选择逻辑或该场景下的特殊分支，最后以最小测试集验证修复结果。

### 影响范围
```yaml
涉及模块:
  - internal/kernel/singbox: 修复 tuic + egress.shadowsocks 的默认出站行为
  - internal/kernel/singbox/config_test.go: 增加最小回归测试
预计变更文件: 2-3
```

### 风险评估
| 风险 | 等级 | 应对 |
|------|------|------|
| 修复点位于 sing-box 特定分支，可能误伤其他协议默认出站 | 中 | 只改 tuic 相关路径并补定向测试 |
| 现象来自运行态而非纯配置生成，静态测试覆盖不足 | 中 | 优先从现有最接近运行态的配置生成/启动路径补最小回归 |
| 本机 Go/缓存环境可能影响验证体验 | 低 | 使用 repo-local `.gocache/.gomodcache` 运行定向测试 |

---

## 3. 技术设计

### 核心排查面
- `buildConfig()` 在 `tuic` 入站下生成的 `route.final`、`outbounds` 与默认 tag 是否一致
- `sing-box` 运行时默认出站选择逻辑是否在该组合下回退到 `direct`
- 现有测试是否只覆盖了 `shadowsocks` 入站，遗漏了 `tuic` 入站组合

### 决策
#### fix-tuic-singbox-shadowsocks-egress#D001: 先补失败回归，再做最小实现修复
**日期**: 2026-03-25
**状态**: 采纳
**背景**: 当前问题已具备明确线上证据，但缺少专门覆盖 `tuic + egress.shadowsocks` 的回归测试。
**选项分析**:
| 选项 | 优点 | 缺点 |
|------|------|------|
| A: 先补失败回归，再修实现 | 修复边界清晰，能锁定真实失效点 | 需要先花一点时间构造用例 |
| B: 直接猜测实现并修改 | 速度快 | 容易修偏，后续难验证 |
**决策**: 选择方案 A
**理由**: 当前静态代码看起来已支持 SS 出站，但线上仍有 direct 行为，先补回归测试才能避免继续靠猜修复。 
**影响**: 主要影响 `internal/kernel/singbox` 模块和对应测试。

---

## 4. 核心场景

### 场景: TUIC 节点启用默认 Shadowsocks 出站
**模块**: `internal/kernel/singbox`
**条件**: `panel.NodeConfig.Protocol=tuic`，且 `kernel.egress.shadowsocks` 完整配置
**行为**: 生成的 sing-box 配置应包含 `default-shadowsocks` outbound，并将默认最终出站指向该 tag
**结果**: 普通 TCP/UDP 连接不应在该组合下无故回退到 `direct`

---

## 5. 成果设计

### 设计方向
- **美学基调**: N/A
- **记忆点**: N/A
- **参考**: N/A

### 视觉要素
- **配色**: N/A
- **字体**: N/A
- **布局**: N/A
- **动效**: N/A
- **氛围**: N/A

### 技术约束
- **可访问性**: N/A
- **响应式**: N/A
