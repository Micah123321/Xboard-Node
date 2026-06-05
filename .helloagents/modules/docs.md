# docs 模块

## 职责

- 维护 `README.md` 与 `config.yml.example` 的操作说明
- 确保新增本地配置项能被直接复制使用

## 当前关键行为

- README 已补充 `kernel.egress.shadowsocks` 的使用说明
- 示例配置已包含传统 SS 与 SS2022 两种写法
- README 与 `config.yml.example` 已明确区分 ACME HTTP-01 的“公网 80 校验”与 `cert.http_port` 的“本地监听端口”语义
- README、`config.yml.example` 与 installer 帮助已统一为 `mi-node` 原生服务、`/etc/mi-node`、`/usr/local/bin/mi-node` 和 `xbctl-linux-*` release artifact；systemd 服务名为 `mi-node.service`，OpenRC 服务名为 `mi-node`
- README 与 MIGRATE 已明确：旧 `Xboard-Node` 迁移成功后由 `mi-node.service` 管理，`--all` 会合并到 `/etc/mi-node/config.yml` 的 `instances:`，不会继续创建 `mi-node@<id>`
- README 与 MIGRATE 已补充 `install.sh egress list/set/clear` 远程入口，用于给已部署节点补充、切换或清除 SOCKS5 / SS / SS2022 默认落地
- `config.yml.example` 已补充 `instances:` 与 machine mode 示例，token 推荐通过 `token_env` 放入 `credentials.env`
- `docs-dns-providers.md` 以 `cert.dns_env` 为准记录 libdns provider 与环境变量别名
- `docs-custom-routes.md` 已按当前代码记录默认保护规则、custom route、panel route 和 final outbound 的真实顺序
