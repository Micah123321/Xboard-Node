# 架构设计

## 总体架构
```mermaid
flowchart TD
    A[配置文件 / 环境变量] --> B[cmd/xboard-node]
    B --> C[internal/config]
    B --> D[internal/service]
    D --> E[internal/panel]
    D --> F[internal/cert]
    D --> G[internal/kernel]
    D --> H[internal/limiter]
    D --> I[internal/tracker]
    D --> J[internal/monitor]
    G --> K[sing-box / xray-core]
    E --> L[Xboard Panel API]
```

## 技术栈
- **后端:** Go 1.25.x
- **通信:** HTTP、WebSocket
- **运行形态:** 单二进制、`systemd` 服务、Docker 容器

## 核心流程
```mermaid
sequenceDiagram
    participant Node as xboard-node
    participant Panel as Xboard Panel
    participant Kernel as Proxy Kernel

    Node->>Panel: POST /api/v2/server/handshake
    Panel-->>Node: 配置、同步策略、WS 参数
    alt 启用 WebSocket
        Node->>Panel: 建立 WebSocket
        Panel-->>Node: 推送配置与用户变更
    else 回退 REST
        Node->>Panel: GET 配置 / 用户
    end
    Node->>Kernel: 启动或热重载
    Node->>Panel: 周期上报流量、在线数、系统状态
```

## 重大架构决策
完整 ADR 记录存储在各变更方案的 `how.md` 中，本章节提供索引。

| adr_id | title | date | status | affected_modules | details |
|--------|-------|------|--------|------------------|---------|
| ADR-20260320-01 | 文档默认推荐原生部署而非 Docker | 2026-03-20 | ✅已采纳 | 安装部署、配置系统 | [history/2026-03/202603200133_docs_cn_native_deploy/how.md#adr-20260320-01-文档默认推荐原生部署而非-docker](../history/2026-03/202603200133_docs_cn_native_deploy/how.md#adr-20260320-01-文档默认推荐原生部署而非-docker) |