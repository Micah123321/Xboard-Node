# xboard-node

Xboard 的专用节点后端，完整兼容 Xboard API，支持 sing-box 与 Xray 两套内核。

> **免责声明**: 本项目仅供学习与研究使用，请自行评估实际部署风险。

## 功能特性

- **双内核支持**: `sing-box`（默认）和 `xray`
- **协议覆盖完整**: 支持 V2Ray、Trojan、Shadowsocks、Hysteria2、TUIC、Naive 等常见协议
- **高效同步**: 优先使用 WebSocket 实时推送，异常时自动回退到 REST 轮询
- **低运维成本**: 单个 Go 二进制即可运行，便于原生部署与多节点管理
- **资源可控**: 支持 `runtime.gomemlimit` 与 `runtime.gogc`，适合小内存主机

## 推荐部署方式：本机直接部署

如果你希望避免 Docker 带来的额外内存占用，推荐直接使用仓库自带的 `install.sh` 原生部署脚本。脚本默认采用二进制 + `systemd` 的方式运行，不加 `--docker` 就是本机部署。

### 适用环境

- Linux 服务器
- 已安装 `bash`
- 建议以 `root` 或 `sudo` 执行
- 支持 Ubuntu 20+、Debian 11+、CentOS 8+、Alpine 3.18+

### 一键部署单节点

在仓库根目录执行：

```bash
bash install.sh \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1
```

### 小内存机器推荐命令

下面这条命令会直接在宿主机部署节点，并额外写入 Go 运行时内存限制，适合希望压低内存占用的场景：

```bash
bash install.sh \
  -a https://panel.example.com \
  -t YOUR_TOKEN \
  -n 1 \
  --gomemlimit 256MiB \
  --gogc 50
```

参数说明：

- `--gomemlimit 256MiB`: 设置 Go 运行时软内存上限，超过后 GC 会更积极
- `--gogc 50`: 将 GC 目标百分比调低，进一步降低峰值内存，但会增加少量 CPU 开销

### 常用管理命令

```bash
bash install.sh list
bash install.sh remove 1
bash install.sh update
bash install.sh uninstall
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
  ghcr.io/cedar2025/xboard-node:latest
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

完整字段请参考 [config.yml.example](config.yml.example)。

## License

MPL-2.0