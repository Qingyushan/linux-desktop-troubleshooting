# 切换到 .deb 与清理

> 返回索引：[README](../README.md) ｜ 原始位置：§6


### 安装

```bash
# 本次用的是 thin deb（约 18MB），运行时会复用已有依赖
pkexec apt-get install -y ./Deepseek.Harness.Desktop_0.25.0_amd64.deb
```

- 包名 `dsh-tauri`，二进制 `/usr/bin/deepseek-harness-desktop`；
- 依赖包含 WebKitGTK、GStreamer、AppIndicator 等；
- 与 AppImage 共用 `~/.local/share/dsh-tauri`（运行时、依赖、设置、日志），所以**不要随手删这个目录**；删了 deb 版首次启动可能要重新下载。

### 清理清单

| 类别 | 处理 |
| - | - |
| AppImage 本体 / `.real` / 包装脚本 | 删除 |
| `~/.local/bin/deepseek-harness-desktop`（同名 wrapper） | 删除，避免遮蔽 `/usr/bin` |
| 指向 AppImage 的 `.desktop` / autostart / 图标副本 | 删除 |
| 主题 `client.js` 补丁、`index.html` 注入 CSS | 用备份还原 |
| `~/.local/share/dsh-render-fix` | 删除 |
| WebKit HTTP 缓存 | 清空，避免旧资源 |
| 实验脚本 `dsh-restart-*` | 删除（或只留脚本，不进菜单） |
| `~/.local/share/dsh-tauri/runtime`、`dependencies` | **保留**，deb 复用 |
| `~/.dsh`（会话、插件、模型凭据） | **保留** |

验证：

```bash
command -v deepseek-harness-desktop   # 必须是 /usr/bin/...
ldd /usr/bin/deepseek-harness-desktop | grep 'not found' || echo OK
xdg-mime query default x-scheme-handler/dsh
```

### 小坑

- `~/.local/bin` 在 PATH 中优先于 `/usr/bin`，旧的 wrapper 会让菜单仍然启动 AppImage（甚至已删除的文件）。
- 切换后自启动项可能丢失；应用设置里的 `auto_start` 不一定自动重建，需要检查 `~/.config/autostart`。
- 桌面端自带的 `dsh` CLI shim 在 `~/.local/bin/dsh`，它指向 `~/.local/share/dsh-tauri`，运行时会自动重建，不要误删。

---
