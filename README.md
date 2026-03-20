# xboard-node

Xboard 的专用节点后端，完整兼容 Xboard API，支持 sing-box 与 Xray 两套内核。

> **免责声明**: 本项目仅供学习与研究使用，请自行评估实际部署风险。

## 功能特性

- **双内核支持**: `sing-box`（默认）和 `xray`
- **协议覆盖完整**: 支持 V2Ray、Trojan、Shadowsocks、Hysteria2、TUIC、Naive 等常见协议
- **高效同步**: 优先使用 WebSocket 实时推送，异常时自动回退到 REST 轮询
- **低运维成本**: 单个 Go 二进制即可运行，便于原生部署与多节点管理
- **资源可控**: 支持 `runtime.gomemlimit` 与 `runtime.gogc`，适合小内存主机
- **出口可控**: 支持默认 SOCKS5 出站，并内置一组私网 / BT / 域名黑名单拦截规则

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

- 这项能力同时支持 `singbox` 和 `xray`
- 当配置了 `kernel.egress.socks5` 后，普通 TCP/UDP 默认出站会走这个 SOCKS5
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
```

完整字段请参考 [config.yml.example](config.yml.example)。

### TLS 证书说明

- 本地配置和安装脚本都支持 `cert_mode: "http"` / `cert_mode: "dns"` 来自动申请 ACME 证书。
- 对于 `tuic`、`hysteria`、`anytls` 以及其他显式开启 `TLS=1` 的协议，服务端必须有可用证书文件才能启动。
- 如果面板和本地配置都没有提供证书，节点会自动在 `{config_dir}/certs` 下生成自签名证书，避免内核因为缺少证书直接启动失败。
- 生产环境仍建议显式配置可信证书，尤其是在客户端不会关闭证书校验的场景。

### 默认拦截规则说明

- 仓库现在默认启用一组内置防滥用规则，会拦截私网访问、BitTorrent 以及一批危险/不希望放行的域名模式。
- 这套规则会在 `singbox` 和 `xray` 两套生成配置中同时生效。
- 即使你没有配置 `kernel.egress.socks5`，这套默认拦截规则也仍然会优先生效。
- 如果你要调整它，可以直接修改 `kernel.egress.enable_default_rules` 和 `kernel.egress.prefer_ipv4`，或者继续补充自己的 `custom_route` / `custom_config` 规则。
- 如果你没有配置 `kernel.egress.socks5`，默认出站仍然是 `direct`；如果配置了，则默认出站会切到这个 SOCKS5。

## 重要说明：Shadowsocks 2022 与 UUID

如果节点使用 `2022-blake3-*` 系列 Shadowsocks cipher，请不要继续把用户密码当普通 `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` 这种 UUID 使用。

- `2022-blake3-aes-128-gcm` 要求标准 base64 编码后的 16 字节密钥
- `2022-blake3-aes-256-gcm` 与 `2022-blake3-chacha20-poly1305` 要求标准 base64 编码后的 32 字节密钥
- 如果面板仍下发 UUID，节点可能在启动阶段报 `invalid shadowsocks 2022 user password`，或在客户端连接阶段出现 `message authentication failed`

推荐做法:

- 如果你的用户体系就是 UUID，请将节点 cipher 改回传统 Shadowsocks，例如 `aes-128-gcm`、`aes-256-gcm`、`chacha20-ietf-poly1305`
- 如果你必须使用 `2022-blake3-*`，请确保服务端 `server_key` 和每个用户密码都使用标准 base64 密钥，而不是 UUID

## License

MPL-2.0
