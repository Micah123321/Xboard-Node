# 服务编排

## 目的
协调面板同步、内核生命周期、用户热更新和状态上报。

## 模块概述
- **职责:** 位于 `internal/service`，负责握手、REST/WS 双通道同步、配置应用、连接跟踪和上报调度。
- **状态:** ✅稳定
- **最后更新:** 2026-03-20

## 规范

### 需求: 在不重启进程的情况下同步节点状态
**模块:** 服务编排
服务层需要尽量通过热更新维持节点持续在线，并在失败时回退到全量重启。

#### 场景: WebSocket 可用
面板在握手时返回 WebSocket 地址。
- 优先建立推送连接
- 配置和用户变更通过事件驱动同步

#### 场景: WebSocket 不可用
面板关闭或断开 WebSocket。
- 回退到 REST 轮询
- 使用指数退避避免持续请求失败

## 依赖
- `internal/panel`
- `internal/kernel`
- `internal/cert`
- `internal/limiter`
- `internal/tracker`
- `internal/monitor`

## 变更历史
- 2026-03-20: 初始化知识库