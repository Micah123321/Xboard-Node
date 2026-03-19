# Changelog

本文件记录项目的重要变更。
格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)，版本号遵循语义化版本。

## [Unreleased]

### 新增
- 增加本机原生一键部署说明，并在安装脚本中支持运行时内存调优参数。

### 变更
- 将公开文档统一调整为简体中文，补充原生部署、源码运行和内存控制说明。
- 在内核启动和用户热更新前增加 Shadowsocks 2022 凭证校验，报错可直接定位 `server_key` 或具体用户 ID。
- 统一当前仓库的 GitHub Actions、Release 下载和安装/更新来源，默认跟随 `Micah123321/Xboard-Node` 的最新发布产物。
