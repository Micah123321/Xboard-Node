# config 模块

## 职责

- 管理本地 `config.yml` 的解析、默认值与运行前校验
- 维护 `kernel.egress` 的结构化配置入口

## 当前关键行为

- `cmd/mi-node` 通过 `config.LoadRoot` / `NormalizeInstances` 启动，兼容 legacy 单节点、`nodes:`、`instances:` 与 machine mode
- `instances:` 可为每个实例定义独立 panel、kernel、runtime、cert、health/debug 端口；machine mode 使用 `machine.machine_id` + `machine.token_env`
- 默认配置根路径统一为 `/etc/mi-node`，配置文件为 `/etc/mi-node/config.yml`，凭据文件为 `/etc/mi-node/credentials.env`
- `install.sh` 通过 `xbctl config init` 生成部署配置；重复安装或迁移多节点时按实例 ID 合并/替换 `instances:`，并合并 `credentials.env`
- 已部署节点的默认落地通过 `xbctl egress list/set/clear` 管理；`install.sh egress ...` 是远程一键入口，内部只透传给 `xbctl egress`
- `kernel.egress.socks5` 与 `kernel.egress.shadowsocks` 互斥
- `kernel.egress.shadowsocks` 支持传统 Shadowsocks 与 `2022-blake3-*`
- `2022-blake3-*` 出站密码支持单 key 与 `<server_key>:<user_key>` 两种格式
- `scripts/migrate-to-mi-node.sh` 会从旧配置迁移 `kernel.egress.socks5` / `kernel.egress.shadowsocks.uri`；SOCKS5 支持结构化字段和 `socks5://user:pass@host:port` URI，认证信息不得写入迁移日志
- 新增最小 `hot-reload` watcher，配置文件变化后仅在新配置可成功 `Load()` 时才触发重启
- 若变更后的配置非法，watcher 只记录错误并保持当前实例继续运行
- `cert.http_port` 是 ACME HTTP-01 的本地监听端口；即使改成其他端口，公网校验入口仍然是 `80`
- `xbctl` 重写 RootConfig 时必须保留实例级 `kernel.egress`、`cert`、`runtime`、`health_port` 和 `debug_port`，避免安装器或迁移脚本写入的实例配置丢失
