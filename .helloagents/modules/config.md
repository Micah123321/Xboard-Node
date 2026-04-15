# config 模块

## 职责

- 管理本地 `config.yml` 的解析、默认值与运行前校验
- 维护 `kernel.egress` 的结构化配置入口

## 当前关键行为

- `kernel.egress.socks5` 与 `kernel.egress.shadowsocks` 互斥
- `kernel.egress.shadowsocks` 支持传统 Shadowsocks 与 `2022-blake3-*`
- `2022-blake3-*` 出站密码支持单 key 与 `<server_key>:<user_key>` 两种格式
- 新增最小 `hot-reload` watcher，配置文件变化后仅在新配置可成功 `Load()` 时才触发重启
- 若变更后的配置非法，watcher 只记录错误并保持当前实例继续运行
- `cert.http_port` 是 ACME HTTP-01 的本地监听端口；即使改成其他端口，公网校验入口仍然是 `80`
