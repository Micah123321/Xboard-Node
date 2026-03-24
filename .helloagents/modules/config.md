# config 模块

## 职责

- 管理本地 `config.yml` 的解析、默认值与运行前校验
- 维护 `kernel.egress` 的结构化配置入口

## 当前关键行为

- `kernel.egress.socks5` 与 `kernel.egress.shadowsocks` 互斥
- `kernel.egress.shadowsocks` 支持传统 Shadowsocks 与 `2022-blake3-*`
- `2022-blake3-*` 出站密码支持单 key 与 `<server_key>:<user_key>` 两种格式
