# xboard-node

Xboard 的专用节点后端，完整兼容 Xboard API，支持 sing-box 与 Xray 两套内核。

> **免责声明**: 本项目仅供学习与研究使用，请自行评估实际部署风险。

## 功能特性

- **双内核支持**: `sing-box`（默认）和 `xray`
- **协议清单明确**: 公共协议与各内核专属协议都已在下方列出，便于直接对照面板配置
- **高效同步**: 优先使用 WebSocket 实时推送，异常时自动回退到 REST 轮询
- **低运维成本**: 单个 Go 二进制即可运行，便于原生部署与多节点管理
- **资源可控**: 支持 `runtime.gomemlimit` 与 `runtime.gogc`，适合小内存主机
- **出口可控**: 支持默认 SOCKS5 出站，并内置一组私网 / BT / 域名黑名单拦截规则

### 当前支持的协议

- `sing-box`（默认）: `vmess`、`vless`、`trojan`、`shadowsocks`、`hysteria`（Version=2 时生成 `hysteria2`）、`tuic`、`naive`、`socks`、`http`、`anytls`、`mieru`
- `xray`: `vmess`、`vless`、`trojan`、`shadowsocks`、`socks`、`http`、`dokodemo-door`
- 两套内核共同支持: `vmess`、`vless`、`trojan`、`shadowsocks`、`socks`、`http`
- `sing-box` 专属: `hysteria` / `hysteria2`、`tuic`、`naive`、`anytls`、`mieru`
- `xray` 专属: `dokodemo-door`

## 推荐部署方式：本机直接部署

如果你希望避免 Docker 带来的额外内存占用，推荐直接通过远程安装脚本进行原生部署。当前仓库远程地址为 `https://github.com/Micah123321/Xboard-Node.git`，一键命令统一从 `dev` 分支的 Raw 脚本拉取并执行；推送到当前仓库 `dev` 分支后，GitHub Actions 会自动更新当前仓库的 Release，`install.sh` 的安装和 `update` 也会默认跟随这里的最新产物。

### 适用环境

- Linux 服务器
- 已安装 `bash`
- 建议以 `root` 或 `sudo` 执行
- 支持 Ubuntu 20+、Debian 11+、CentOS 8+、Alpine 3.18+

### 一键部署单节点

直接执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1
```

### 小内存机器推荐命令

下面这条命令会直接在宿主机部署节点，并额外写入 Go 运行时内存限制，适合希望压低内存占用的场景：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1 \
  --gomemlimit 256MiB \
  --gogc 50
```

参数说明：

- `--gomemlimit 256MiB`: 设置 Go 运行时软内存上限，超过后 GC 会更积极
- `--gogc 50`: 将 GC 目标百分比调低，进一步降低峰值内存，但会增加少量 CPU 开销

### 一键申请 ACME 证书

如果你的节点协议需要 TLS，安装脚本现在可以直接写入证书配置。

使用 ACME HTTP-01：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1 \
  --cert-domain node.example.com
```

- 仅传 `--cert-domain` 时，安装脚本会默认写入 `cert_mode: "http"`
- 你需要保证域名已经解析到当前服务器，且公网可以访问 `80` 端口

使用 ACME DNS-01：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1 \
  --cert-mode dns \
  --cert-domain node.example.com \
  --cert-dns-provider cloudflare \
  --cert-dns-env CF_API_TOKEN=YOUR_TOKEN
```

- 部署完成后，安装脚本会先等待最多约 15 秒再输出“证书申请状态”：检测到 `/etc/xboard-node/<node_id>/certs/<domain>.crt/.key` 即表示申请成功；否则会提示你查看服务日志继续排查。
- 当前内置支持 `cloudflare` 和 `alidns`
- DNS-01 适合被 CDN 代理、无法开放 `80` 端口，或需要通配符证书的场景

### 默认 SOCKS5 出站

如果你希望所有默认出站流量都先走一个上游 SOCKS5，可以在安装时直接传入：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1 \
  --egress-socks5 127.0.0.1:1080
```

如果 SOCKS5 需要认证：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1 \
  --egress-socks5 127.0.0.1:1080 \
  --egress-socks5-user your-user \
  --egress-socks5-pass your-pass
```

如果默认出站需要走传统 Shadowsocks：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1 \
  --egress-shadowsocks-uri 'ss://YWVzLTEyOC1nY206eW91ci1wYXNzd29yZA==@127.0.0.1:8388'
```

如果默认出站需要走 SS2022：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1 \
  --egress-shadowsocks-uri 'ss://MjAyMi1ibGFrZTMtYWVzLTI1Ni1nY206ODhvMGZwK3BBV29XS3ZrRGUydWhxek4zcDE3Uk5mQzdhSE0wVldJTUtuZz06UnlObkhsZ3lLT3ZKVzRCWVY5TnhWMDlMWkhnWGM1Ui9wamxKSjRPR3QyND0=@38.182.122.32:37605?type=tcp#egress'
```

- 这项能力同时支持 `singbox` 和 `xray`
- 当配置了 `kernel.egress.socks5` 后，普通 TCP/UDP 默认出站会走这个 SOCKS5
- 如果你更需要接入 `ss` / `ss2022` 落地节点，也可以改用 `kernel.egress.shadowsocks`；默认路由行为与 `socks5` 保持一致，但两者只能二选一
- `install.sh` 现在使用单个 `--egress-shadowsocks-uri 'ss://...'` 参数写入默认 SS 出站
- `kernel.egress.shadowsocks` 现在只接受 `uri`；旧的 `address / port / method / password` 写法会在加载配置时直接报错
- `aes-192-gcm` 仅建议在 `singbox` 内核下使用；当前安装脚本会拦截 `xray + aes-192-gcm` 组合，避免写入后启动失败
- 如果未配置 SOCKS5，默认出站仍然是直连，但默认拦截规则依然会照常生效
- 安装脚本生成的 `config.yml` 会默认写出 `kernel.egress.enable_default_rules: true` 和 `kernel.egress.prefer_ipv4: true`，你可以直接在本地改这两个开关

### 常用管理命令

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) list
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) remove 1
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) update
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) uninstall
```

原生部署完成后可使用：

```bash
systemctl status xboard-node@1
journalctl -u xboard-node@1 -f
systemctl restart xboard-node@1
```

## 本地 SS 出站调试端口

如果你需要确认 `sing-box + kernel.egress.shadowsocks` 是否真的成为默认出站，可以额外开启一个只监听本机回环地址的调试端口：

```yaml
debug_port: 65531
```

- 监听地址固定为 `127.0.0.1:<debug_port>`，不会暴露到公网
- 调试接口路径为 `http://127.0.0.1:<debug_port>/debug/egress`
- 返回内容包含 `default_outbound_tag`
- 返回内容包含 `shadowsocks_upstream.address / port / method`
- 返回内容包含 `last_probe`（最近一次通过当前默认出站发起的真实 TCP 拨号检查结果）
- 当前只对 `sing-box + kernel.egress.shadowsocks` 启用真实 probe；未启用 SS 出站或非 sing-box 内核时，会在返回 JSON 里明确说明

示例：

```bash
curl http://127.0.0.1:65531/debug/egress
```

## 可选方案：Docker 部署

如果你更关注环境隔离，可以继续使用 Docker。只是对于小内存机器，通常更推荐上面的原生部署方式。

```bash
docker run -d --restart=always --network=host \
  -e apiHost=https://panel.example.com \
  -e apiKey=YOUR_TOKEN \
  -e nodeID=1 \
  ghcr.io/micah123321/xboard-node:latest
```

## 源码构建

### 构建当前平台二进制

```bash
make build
```

### 构建 Linux 版本

```bash
make build-linux
make build-linux-arm64
```

### 运行测试

```bash
go test ./...
```

## 配置说明

最小配置示例：

```yaml
panel:
  url: "https://panel.example.com"
  token: "your-server-token"
  node_id: 1

kernel:
  type: "singbox"
  config_dir: "/etc/xboard-node"
  log_level: "warn"

log:
  level: "info"
  output: "stdout"
debug_port: 65531
```

如果需要进一步压低内存使用，可以增加 `runtime` 配置：

```yaml
runtime:
  gomemlimit: "256MiB"
  gogc: 50
```

说明：

- `gomemlimit` 建议从机器可用内存的 60% 到 80% 开始尝试
- `gogc` 越低，内存越省，但 CPU 消耗会更高
- 多节点部署时建议为每个节点单独设置 `config_dir`

如果需要默认经 SOCKS5 出站，可以增加：

```yaml
kernel:
  egress:
    enable_default_rules: true
    prefer_ipv4: true
    socks5:
      address: "127.0.0.1"
      port: 1080
      # username: "your-user"
      # password: "your-pass"
    # shadowsocks:
    #   uri: "ss://MjAyMi1ibGFrZTMtYWVzLTI1Ni1nY206ODhvMGZwK3BBV29XS3ZrRGUydWhxek4zcDE3Uk5mQzdhSE0wVldJTUtuZz06UnlObkhsZ3lLT3ZKVzRCWVY5TnhWMDlMWkhnWGM1Ui9wamxKSjRPR3QyND0=@38.182.122.32:37605?type=tcp#egress"
    #   # 传统 SS 示例：
    #   # uri: "ss://YWVzLTEyOC1nY206eW91ci1wYXNzd29yZA==@127.0.0.1:8388"
```

完整字段请参考 [config.yml.example](config.yml.example)。

### TLS 证书说明

- 本地配置和安装脚本都支持 `cert_mode: "http"` / `cert_mode: "dns"` 来自动申请 ACME 证书。
- 对于 `tuic`、`hysteria`（Version=2 时对应 `hysteria2`）、`anytls` 以及其他显式开启 `TLS=1` 的协议，服务端必须有可用证书文件才能启动。
- 如果面板和本地配置都没有提供证书，节点会自动在 `{config_dir}/certs` 下生成自签名证书，避免内核因为缺少证书直接启动失败。
- 生产环境仍建议显式配置可信证书，尤其是在客户端不会关闭证书校验的场景。

### 默认拦截规则说明

- 仓库现在默认启用一组内置防滥用规则，会拦截私网访问、BitTorrent 以及一批危险/不希望放行的域名模式。
- 这套规则会在 `singbox` 和 `xray` 两套生成配置中同时生效。
- 即使你没有配置 `kernel.egress.socks5` 或 `kernel.egress.shadowsocks`，这套默认拦截规则也仍然会优先生效。
- 如果你要调整它，可以直接修改 `kernel.egress.enable_default_rules` 和 `kernel.egress.prefer_ipv4`，或者继续补充自己的 `custom_route` / `custom_config` 规则。
- 如果你没有配置任何默认上游出站，默认出站仍然是 `direct`；如果配置了 `kernel.egress.socks5` 或 `kernel.egress.shadowsocks`，默认出站会切到对应的上游。

## 重要说明：Shadowsocks 2022 与 UUID

如果节点使用 `2022-blake3-*` 系列 Shadowsocks cipher，请不要继续把用户密码当普通 `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` 这种 UUID 使用。

- `2022-blake3-aes-128-gcm` 要求标准 base64 编码后的 16 字节密钥
- `2022-blake3-aes-256-gcm` 与 `2022-blake3-chacha20-poly1305` 要求标准 base64 编码后的 32 字节密钥
- 如果面板仍下发 UUID，节点可能在启动阶段报 `invalid shadowsocks 2022 user password`，或在客户端连接阶段出现 `message authentication failed`

推荐做法:

- 如果你的用户体系就是 UUID，请将节点 cipher 改回传统 Shadowsocks，例如 `aes-128-gcm`、`aes-256-gcm`、`chacha20-ietf-poly1305`
- 如果你必须使用 `2022-blake3-*`，请确保服务端 `server_key` 和每个用户密码都使用标准 base64 密钥，而不是 UUID
- 如果你把它配置在 `kernel.egress.shadowsocks.uri` 里，URI 解码后的 `method:password` 中仍然使用标准 base64 key；多用户或中转场景依然是 `<server_key>:<user_key>`

## License

MPL-2.0
