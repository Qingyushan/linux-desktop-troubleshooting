# 安装 QQ、微信、Steam

> 返回索引：[README](../README.md) ｜ 原始位置：§2


### 结果

| 软件 | 版本 | 来源 |
| - | - | - |
| 微信 | 4.1.13.26 | 腾讯官方 deb |
| QQ | 3.2.32-52194 | 官方安装包（官网 3.2.34 直链当时返回 403） |
| Steam | 1.0.0.85 | Ubuntu multiverse `steam-installer`，含 199 个依赖（已启用 i386） |

### 关键点

- QQ / 微信的官方 Linux 包依赖 `libgtk-3-0`，在 Ubuntu 26.04 上由 `libgtk-3-0t64` 提供（`Provides: libgtk-3-0`），apt 能自动满足。
- Steam 需要 32 位库，`dpkg --print-foreign-architectures` 必须包含 `i386`；`steam-installer` 会拉入大量 `:i386` 包。
- NVIDIA 双显卡机器，Steam 游戏还需要 `nvidia-driver-libs:i386`（本次未装，属于可选）。
- S302 的 hosts 条目会让 `github.com` / Steam 域名在 S302 未运行时变成“连接被拒绝”；关 S302 前要清 hosts（或至少知道这个因果）。

---
