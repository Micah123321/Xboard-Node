# 面板客户端

## 目的
封装与 Xboard 面板的 HTTP / WebSocket 通信协议。

## 模块概述
- **职责:** 位于 `internal/panel`，负责握手、获取配置、获取用户、上报指标以及解析面板响应结构。
- **状态:** ✅稳定
- **最后更新:** 2026-03-20

## 规范

### 需求: 面板通信具备兼容性与容错
**模块:** 面板客户端
客户端必须兼容握手接口、传统配置接口和用户接口，并支持 ETag 缓存。

#### 场景: 配置未变化
面板返回 `304 Not Modified`。
- 返回空结果
- 由上层保留当前运行配置

#### 场景: 面板返回弱类型字段
响应中字段类型不完全稳定。
- 使用弱类型解码
- 在缺失关键字段时拒绝应用配置

## API接口
### `POST /api/v2/server/handshake`
**描述:** 获取初始同步配置。

### `GET /api/v1/server/UniProxy/config`
**描述:** 获取节点配置。

### `GET /api/v1/server/UniProxy/user`
**描述:** 获取用户列表。

### `POST /api/v2/server/report`
**描述:** 上报运行状态与扩展指标。

## 依赖
- `net/http`
- `gorilla/websocket`
- `mapstructure`

## 变更历史
- 2026-03-20: 初始化知识库