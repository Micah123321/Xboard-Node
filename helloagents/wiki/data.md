# 数据模型

## 概述
本项目不维护独立数据库，核心数据模型由本地 YAML 配置、面板下发的节点配置以及运行时统计组成。

---

## 配置模型

### `config.Config`

**描述:** 节点启动时加载的主配置对象。

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| panel | object | 必填 | 面板地址、令牌、节点标识 |
| node | object | 可选 | 推送与拉取间隔 |
| kernel | object | 可选 | 内核类型、配置目录、日志等级 |
| cert | object | 可选 | 证书模式、证书路径、DNS 提供商 |
| log | object | 可选 | 日志等级与输出位置 |
| runtime | object | 可选 | `gomemlimit`、`gogc` 运行时内存调优 |
| health_port | integer | 可选 | 健康检查端口，0 表示关闭 |
| nodes | array | 可选 | 多节点模式列表 |

### `config.NodeEntry`

**描述:** 多节点模式下的单个节点定义。

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| node_id | integer | 必填，正整数 | 面板中的节点 ID |
| node_type | string | 可选 | 节点类型覆盖 |
| kernel | object | 可选 | 单节点内核配置覆盖 |
| cert | object | 可选 | 单节点证书配置覆盖 |

### `config.RuntimeConfig`

**描述:** Go 运行时内存调优配置。

| 字段名 | 类型 | 约束 | 说明 |
|--------|------|------|------|
| gomemlimit | string | 可选 | 软内存上限，例如 `256MiB` |
| gogc | integer | 可选 | GC 目标百分比，例如 `50` |

---

## 运行态模型

### 面板配置 `panel.NodeConfig`

**描述:** 由面板返回的节点协议、端口、证书和其他代理参数。

### 用户数据 `panel.User`

**描述:** 用户标识、UUID、设备限制、速率限制等授权信息。

### 指标数据 `monitor.Status`

**描述:** CPU、内存、磁盘、交换区、负载、GC 和运行时信息，用于上报面板。