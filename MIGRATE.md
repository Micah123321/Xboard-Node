# 旧 Xboard-Node 批量迁移到 mi-node

本文档对应仓库内脚本 [scripts/migrate-to-mi-node.sh](scripts/migrate-to-mi-node.sh)。

远程执行时，统一使用这个 raw 地址：

```bash
https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh
```

目标场景：

- 机器上已经运行旧 `Xboard-Node`
- 不同机器的域名、节点 ID、证书配置都不一样
- 希望尽量不手填参数，直接远程执行完成切换

## 脚本做了什么

脚本会在目标机器上自动完成这些步骤：

- 搜索旧配置文件，支持这些位置：
  - `/etc/xboard-node/*/config.yml`
  - `/etc/xboard-node/config.yml`
  - `/etc/Xboard-Node/*/config.yml`
  - `/etc/Xboard-Node/config.yml`
  - `/etc/mi-node/*/config.yml`
  - `/etc/mi-node/config.yml`
- 自动读取这些配置项：
  - `panel.url`
  - `panel.token`
  - `panel.node_id`
  - `kernel.type`
  - `cert.cert_mode`
  - `cert.domain`
  - `cert.email`
  - `cert.http_port`
  - `cert.dns_provider`
  - `cert.dns_env`
  - `runtime.gomemlimit`
  - `runtime.gogc`
- 迁移前自动备份旧配置和相关 service 定义
- 停掉旧 `xboard-node` / 旧模板 `mi-node@<id>` 服务，避免端口冲突
- 用识别出的参数重新执行 `mi-node` 的 `install.sh`
- 写入或合并到 `/etc/mi-node/config.yml` 的 `instances:`，单机多节点 `--all` 会保留已迁移节点并追加/替换当前节点
- 迁移成功后由 `mi-node.service` 管理，并禁用旧 `xboard-node` 服务

## 适用方式

### 1. 单机单节点，最省事

如果一台机器上只有一个节点配置，直接远程执行：

```bash
ssh root@YOUR_HOST "bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh)"
```

### 2. 单机多节点，迁移指定节点

```bash
ssh root@YOUR_HOST "bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh) --node-id 330"
```

### 3. 单机多节点，整机全部迁移

```bash
ssh root@YOUR_HOST "bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh) --all"
```

## 批量执行

准备一个 `servers.txt`，每行一个服务器地址：

```txt
1.2.3.4
5.6.7.8
example-host
```

然后在本地仓库目录执行：

```bash
while read -r host; do
  [ -z "$host" ] && continue
  echo "===== ${host} ====="
  ssh -o BatchMode=yes "root@${host}" "bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh) --all"
done < servers.txt
```

如果你的机器基本都是“每台 1 个节点”，可以把 `--all` 去掉：

```bash
while read -r host; do
  [ -z "$host" ] && continue
  echo "===== ${host} ====="
  ssh -o BatchMode=yes "root@${host}" "bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh)"
done < servers.txt
```

## 先看不执行

如果你想先确认脚本识别到了哪些参数，可以加 `--dry-run`：

```bash
ssh root@YOUR_HOST "bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh) --dry-run"
```

脚本只会打印将要执行的 `mi-node install.sh` 命令，不会真正停服务或安装。

## 备份位置

默认备份目录：

```bash
/root/mi-node-migrate-YYYYMMDD-HHMMSS/
```

可以手动指定：

```bash
ssh root@YOUR_HOST "bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh) --backup-root /root/custom-migrate-backup"
```

## 切换后怎么继续更新

第一次切到 `mi-node` 成功后，后续就不需要再传域名、节点 ID 这些参数了。

直接在目标机器执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/install.sh) update
```

这条命令会：

- 下载最新 `mi-node` 二进制
- 下载最新 `xbctl` 管理工具
- 如果当前是新版原生部署并且 `mi-node.service` 正在运行，会自动重启 `mi-node.service`

如果某台机器仍然是旧模板部署，也就是还在运行 `mi-node@<id>`，`update` 只会更新二进制，不会自动重启这些旧模板实例。此时需要补一次：

```bash
systemctl list-units 'mi-node@*.service' --state=active --no-legend --no-pager \
  | awk '{print $1}' \
  | xargs -r systemctl restart
```

## 建议执行顺序

建议先拿 1 台旧机器验证：

```bash
ssh root@YOUR_HOST "bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh) --dry-run"
ssh root@YOUR_HOST "bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/mi-node/refs/heads/dev/scripts/migrate-to-mi-node.sh)"
ssh root@YOUR_HOST 'systemctl status mi-node --no-pager'
```

确认单机无误后，再批量跑全量服务器。

## 风险边界

- 脚本依赖旧配置仍然是标准 YAML 结构
- 如果一台机器上有多个节点，而你没有传 `--node-id` 或 `--all`，脚本会拒绝执行
- 如果旧配置缺少 `panel.url` / `panel.token` / `panel.node_id`，脚本会直接退出，不会盲目安装
- 脚本默认会在迁移成功后禁用旧 `xboard-node` 服务；如果你想暂时保留旧服务启用状态，可以加 `--keep-old-enabled`
