# 归档索引

| 时间戳 | 名称 | 类型 | 涉及模块 | 决策 | 结果 |
|--------|------|------|----------|------|------|
| 202604152142 | install-http01-preflight | implementation | install, docs, config | install-http01-preflight#D001 不伪造任意公网端口 HTTP-01，改为增强预检与提示 | ✅完成 |
| 202603250540 | install-ss-egress-healthcheck | implementation | install, docs | install.sh 在 singbox + SS egress 场景下等待默认出站 probe，失败即判部署失败并保留现场 | 已完成 |
| 202603250302 | merge-upstream-compat-fixes | implementation | kernel | 本地主线 + 选择性吸收上游协议兼容性修复 | 已完成 |
| 202603250316 | minimal-hot-reload | implementation | config, bootstrap | 仅吸收 hot-reload，排除 nlog 与并发重构 | 已完成 |
