# 安装部署

## 目的
定义项目的推荐部署方式、安装脚本能力和运维入口。

## 模块概述
- **职责:** 由根目录 `install.sh`、`README.md`、`config.yml.example` 共同提供，负责原生部署、Docker 部署、多节点管理和运行时内存调优说明。
- **状态:** ✅稳定
- **最后更新:** 2026-03-20

## 规范

### 需求: 提供可重复的一键部署方式
**模块:** 安装部署
文档必须优先给出本机原生部署方案，Docker 作为可选补充，而不是默认路径。

#### 场景: 单节点本机部署
运维人员希望减少 Docker 额外内存开销。
- 使用 `bash <(curl -fsSL https://raw.githubusercontent.com/Micah123321/Xboard-Node/refs/heads/dev/install.sh) -a <url> -t <token> -n <node_id>`
- 通过 `systemd` 管理单个节点进程

#### 场景: 受限内存机器
机器内存较小或多个节点共用主机。
- 支持在安装阶段写入 `runtime.gomemlimit`
- 支持在安装阶段写入 `runtime.gogc`

#### 场景: Shadowsocks 2022 密钥格式
节点使用 `2022-blake3-*` 系列 Shadowsocks cipher。
- 用户密码必须是标准 base64 编码后的 16/32 字节密钥，不能直接使用 UUID
- 如面板仍使用 UUID 用户体系，应改回传统 Shadowsocks cipher

#### 场景: 当前仓库自动发布与安装
当前仓库 `Micah123321/Xboard-Node` 推送到 `dev` 分支，或手动触发 workflow 后，需要自动产出可安装版本。
- GitHub Actions 自动更新当前仓库的 Release 资产
- `install.sh` 与 `update` 默认从当前仓库下载最新二进制
- Docker 默认拉取 `ghcr.io/micah123321/xboard-node:latest`

## 变更历史
- [202603200133_docs_cn_native_deploy](../../history/2026-03/202603200133_docs_cn_native_deploy/) - 补充中文文档、原生部署说明与内存调优参数
- 2026-03-20: 统一当前仓库的 Action、Release 和安装脚本来源，安装与更新默认跟随 `Micah123321/Xboard-Node`


