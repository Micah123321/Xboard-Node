# xboard-node

> 本文件包含项目级别的核心信息。详细模块说明见 `modules/` 目录。

---

## 1. 项目概述

### 目标与背景
`xboard-node` 是 Xboard 面板的专用节点后端，实现与面板的配置同步、用户同步、流量上报以及代理内核驱动。

### 范围
- **范围内:** 面板 API 对接、WebSocket 与 REST 回退、sing-box/Xray 内核控制、证书管理、限速与在线统计
- **范围外:** 面板前端、数据库持久化、Docker 编排平台管理

### 干系人
- **负责人:** 仓库维护者与节点运维人员

---

## 2. 模块索引

| 模块名称 | 职责 | 状态 | 文档 |
|---------|------|------|------|
| 启动入口 | 参数解析、配置加载、进程生命周期管理 | ✅稳定 | [modules/bootstrap.md](modules/bootstrap.md) |
| 配置系统 | YAML 与环境变量加载、默认值、校验、多节点展开 | ✅稳定 | [modules/config.md](modules/config.md) |
| 服务编排 | 面板握手、配置应用、数据上报、运行时调度 | ✅稳定 | [modules/service.md](modules/service.md) |
| 面板客户端 | 调用握手、配置、用户、上报等 API | ✅稳定 | [modules/panel.md](modules/panel.md) |
| 内核适配 | 抽象 sing-box / xray 的启动与热更新 | ✅稳定 | [modules/kernel.md](modules/kernel.md) |
| 证书管理 | 处理自动证书、面板下发证书与本地证书 | ✅稳定 | [modules/cert.md](modules/cert.md) |
| 限速与监控 | 连接统计、限速、在线 IP、系统指标采集 | ✅稳定 | [modules/ops.md](modules/ops.md) |
| 安装部署 | 一键安装脚本、systemd 模板、Docker Compose 生成 | ✅稳定 | [modules/install.md](modules/install.md) |

---

## 3. 快速链接
- [技术约定](../project.md)
- [架构设计](arch.md)
- [API 手册](api.md)
- [数据模型](data.md)
- [变更历史](../history/index.md)