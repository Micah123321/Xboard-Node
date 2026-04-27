# docs 模块

## 职责

- 维护 `README.md` 与 `config.yml.example` 的操作说明
- 确保新增本地配置项能被直接复制使用

## 当前关键行为

- README 已补充 `kernel.egress.shadowsocks` 的使用说明
- 示例配置已包含传统 SS 与 SS2022 两种写法
- README 与 `config.yml.example` 已明确区分 ACME HTTP-01 的“公网 80 校验”与 `cert.http_port` 的“本地监听端口”语义
- README、`config.yml.example` 与 installer 帮助已统一为 `mi-node.service`、`/etc/mi-node`、`/usr/local/bin/mi-node` 和 `xbctl-linux-*` release artifact
- `config.yml.example` 已补充 `instances:` 与 machine mode 示例，token 推荐通过 `token_env` 放入 `credentials.env`
- `docs-dns-providers.md` 以 `cert.dns_env` 为准记录 libdns provider 与环境变量别名
- `docs-custom-routes.md` 已按当前代码记录默认保护规则、custom route、panel route 和 final outbound 的真实顺序
