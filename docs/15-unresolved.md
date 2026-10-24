# 尚未解决 / 后续

> 返回索引：[README](../README.md) ｜ 原始位置：§11


- DSH 的渲染问题只做到“deb 明显改善”，没有定位到 WebKit 的具体 bug；如果再次出现“仅 resize 刷新”，优先试 `WEBKIT_FORCE_VBLANK_TIMER=1`，并记录 WebKitGTK 版本。
- 7 个外部插件仍未挂载；需要在应用内重新启用，或重跑安装并确认 `dsh.profile.bundles`。
- Office 运行时未初始化，启用 office-kit 后首次使用会 bootstrap；如失败再手动跑 `postinstall.mjs`。
- 更新检查的 GitHub API 301 未处理；属于应用侧问题。

---
