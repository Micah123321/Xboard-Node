# 变更提案: 当前仓库 Release 与安装源统一

## 需求背景
当前仓库的 README 已切换到 `Micah123321/Xboard-Node`，但 GitHub Actions 中的 GHCR 推送路径和 `install.sh` 中的二进制下载地址仍指向旧上游 `cedar2025/xboard-node`。这会导致 Action 产物、Release 下载和安装/更新来源不一致，无法保证脚本安装的是当前仓库最新版本。

## 变更内容
1. 将 GitHub Actions 的 Docker 镜像推送目标改为当前仓库对应的 GHCR 路径。
2. 调整 Release 产出策略，使推送到当前仓库后可以自动生成并更新 Release 资产。
3. 修改安装/更新脚本与文档，默认下载当前仓库的最新版本。

## 影响范围
- **模块:** CI/CD、安装部署、运维文档
- **文件:** `.github/workflows/ci.yml`、`install.sh`、`README.md`
- **API:** 无
- **数据:** 更新知识库、方案包与变更记录

## 核心场景

### 需求: 当前仓库自动产出可安装版本
**模块:** CI/CD
开发者将代码推送到当前仓库后，希望自动得到可下载的 Release 资产和镜像。

#### 场景: 推送到 dev 分支
提交进入当前仓库的 `dev` 分支。
- 自动构建 Linux 二进制
- 自动更新当前仓库 Release
- 自动推送当前仓库 GHCR 镜像

### 需求: 安装脚本始终跟随当前仓库
**模块:** 安装部署
用户从当前仓库执行安装和更新时，不应再访问旧上游地址。

#### 场景: 首次安装或执行 update
用户执行 `install.sh` 安装或升级。
- 默认下载当前仓库的 Release 资产
- Docker 镜像默认拉取当前仓库 GHCR 地址

## 风险评估
- **风险:** Release 策略与 `releases/latest` 下载策略不一致，导致脚本仍更新不到最新构建
- **缓解:** 同步调整 Action 的 latest 标记与安装脚本的下载回退逻辑，并执行脚本语法检查与目标测试
