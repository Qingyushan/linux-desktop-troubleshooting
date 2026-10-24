# 功能体检（deb 版）

> 返回索引：[README](../README.md) ｜ 原始位置：§7


| 功能 | 状态 | 备注 |
| - | - | - |
| 桌面进程 / 3080 服务 | ✅ | 启动 3 秒内 ready |
| 模型 / 对话 / 附件 | ✅ | 模型列表 2 个 |
| 通知 | ✅ | `notify-send` 与系统通知通道正常 |
| 托盘 | ✅ | `StatusNotifierItem` 已注册，Ubuntu AppIndicator 扩展启用 |
| 宠物 | ✅ | 宠物窗口存在，SSE 流返回 keepalive |
| `dsh://` | ✅ | handler 指向 `/usr/bin/deepseek-harness-desktop` |
| inotify | ✅ 已修 | 65536 → 524288，写入 `/etc/sysctl.d/99-dsh-inotify.conf` |
| 自启动 | ✅ 已补 | `~/.config/autostart/deepseek-harness-desktop.desktop` |
| 外部插件 | ⚠️ 未挂载 | 7 个插件已安装但不在 profile `bundles` |
| Office 运行时 | ⚠️ 未初始化 | `~/.dsh/office/runtime` 不存在 |
| 更新检查 | ⚠️ | GitHub API 301 / 请求失败，回退 atom |
| 手机远程 | ⏸ 未启用 | 23332 未监听 |
| 定时任务 | ⏸ 无任务 | 插件已加载 |
| 工作树 | ⏸ 不适用 | 工作区不是 Git 仓库 |

### 外部插件问题

已安装但未挂载：

```
dsh-better-sidebar, dsh-ops, dsh-office-kit, dsh-rewind-plugin,
billion-context, @changfenhuang/dsh-genui, dshmarket
```

原因：`pnpm add` 因 `ERR_PNPM_IGNORED_BUILDS: dsh-office-kit` 退出 1，插件包下载了但没有注册进 profile 的 `dsh.profile.bundles`。`pnpm-workspace.yaml` 里后来已有 `allowBuilds` / `onlyBuiltDependencies`，重试安装理论上能过；启用后需要重启应用。

---
