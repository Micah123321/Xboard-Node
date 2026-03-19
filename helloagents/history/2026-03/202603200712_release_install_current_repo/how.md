# 实施方案: 当前仓库 Release 与安装源统一

## 方案概述
将仓库来源收敛为单一事实来源 `Micah123321/Xboard-Node`，同时在 Action 内尽量使用 `github.repository`、`github.repository_owner` 和仓库名计算当前 GHCR 路径。安装脚本则默认指向当前仓库，并对 latest/dev Release 做回退下载，避免 Release 标签切换时出现安装失败。

## 实施步骤
1. 更新 `.github/workflows/ci.yml`：
   - 跳过 PR 场景下的镜像推送
   - 计算当前仓库的 GHCR 镜像地址
   - 统一 Release 生成策略，使 dev 推送产物可被安装脚本获取
2. 更新 `install.sh`：
   - 抽出当前仓库、Release、GHCR 的公共变量
   - 安装与更新统一从当前仓库下载
   - Docker 镜像和 systemd 文档链接改为当前仓库
3. 更新 README 与知识库说明，使文档与脚本行为一致。
4. 验证 `bash -n install.sh` 和相关 Go 测试，完成知识库与方案包归档。

## 关键决策
- Action 使用当前 GitHub 仓库上下文计算 GHCR 地址，避免再次写死旧上游。
- 安装脚本默认使用当前仓库常量，同时保留环境变量覆盖能力。
- 下载逻辑优先 `latest`，失败时回退到 `dev` tag，兼容当前仓库的开发发布流程。

## 验证策略
- `bash -n install.sh`
- 针对 workflow 和文档做静态检查
- 复查仓库内所有 `cedar2025/xboard-node` 旧来源是否已替换
