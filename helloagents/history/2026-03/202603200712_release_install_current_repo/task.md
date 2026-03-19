# 任务清单: 当前仓库 Release 与安装源统一

> **状态:** 已完成（`bash -n install.sh` 因当前 Windows 环境无权执行 `bash.exe` 未能运行；其余静态检查已完成）

目录: `helloagents/history/2026-03/202603200712_release_install_current_repo/`

---

## 1. CI/CD
- [√] 1.1 调整 GitHub Actions 的 GHCR 推送目标到当前仓库
- [√] 1.2 调整当前仓库的 Release 自动生成策略

## 2. 安装脚本
- [√] 2.1 将安装与更新下载地址改为当前仓库
- [√] 2.2 将 Docker 镜像与文档链接改为当前仓库
- [√] 2.3 增加下载回退逻辑，兼容 latest/dev Release

## 3. 文档与知识库
- [√] 3.1 更新 README 中的 Docker 与发布说明
- [√] 3.2 更新 `helloagents/wiki/modules/install.md`
- [√] 3.3 更新 `helloagents/CHANGELOG.md`

## 4. 验证
- [X] 4.1 执行 `bash -n install.sh`（失败原因: 当前 Windows 环境无法访问 `C:\Users\xiaohuli\AppData\Local\Microsoft\WindowsApps\bash.exe`）
- [√] 4.2 复查当前生效文件中的旧上游地址已移除
- [√] 4.3 迁移方案包并更新 `helloagents/history/index.md`
