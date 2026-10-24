# DSH 日常用 Web 端：无头服务 + 网页快捷方式（开机不弹客户端窗口）

> 返回索引：[README](../README.md) ｜ 相关脚本：无（用 systemd user 服务 + 两个启动器）

## 为什么要这么改

- DSH 桌面客户端是 Tauri + WebKitGTK。本机实测**不是软件渲染**（`nvidia-smi pmon` 里它是 NVIDIA graphics client，打开 renderD129、持有 dma-buf），但同一个 WebKit 引擎测「毛玻璃 + 动画」页面四种模式都只有 62 fps，说明瓶颈在**页面本身**（95 个客户端插件、0.9 MB 入口 JS、`backdrop-filter` 毛玻璃），而 Firefox 的 WebRender 处理这类负载明显更顺。
- 结论：**日常用 Firefox 打开 `http://127.0.0.1:3080`**，桌面客户端只在需要托盘/宠物时人工启动。

于是要做两件事：

1. 后端改成**无头常驻**（跑 harness web 服务，不创建任何窗口）；
2. 加一个**网页快捷方式**，点一下就能在 Firefox 里打开（后端没起会自动拉起）。

## 改了哪些东西

| 文件 | 作用 |
| --- | --- |
| `~/.config/systemd/user/dsh-harness.service` | 登录时以 systemd user 服务启动 harness（profile `better-deepseek-harness-codex`，端口 3080），无窗口 |
| `~/.local/bin/dsh-web` | 打开 web 端：3080 通就直接开 Firefox；不通就 `systemctl --user start dsh-harness`，等 60 秒；还不行就退回启动桌面客户端（保证总有 UI） |
| `~/.local/share/applications/dsh-web.desktop` | 应用菜单项「DeepSeek Harness（网页版）」 |
| `~/桌面/DeepSeek Harness（网页版）.desktop` | 桌面图标（已 `chmod +x` + `metadata::trusted`） |
| `~/.local/bin/dsh-client` + `dsh-client.desktop` | 需要桌面客户端时用：会先 `systemctl --user stop dsh-harness`（避免 3080 冲突）再启动客户端 |
| 关闭 `~/.config/autostart/deepseek-harness-desktop.desktop` | 已挪到 `~/.config/autostart-disabled/`，开机不再弹客户端界面 |

服务单元的关键内容：

```ini
[Service]
Environment=DSH_HOME=/home/qys/.dsh
Environment=PATH=/home/qys/.local/bin:...:/snap/bin        # 必须带 PATH
ExecStart=/home/qys/.local/share/dsh-tauri/runtime/bin/node --max-old-space-size=7695 \
  /home/qys/.local/share/dsh-tauri/dependencies/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js \
  --profile better-deepseek-harness-codex --port 3080
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
```

> `PATH` 这条别省：systemd 服务的 PATH 是精简版，不带 `~/.local/bin` 的话，harness 里调用 `dsh` / `pnpm` / 自定义脚本会找不到命令。

## 与 quiet-startup 扩展的关系

改成无头服务后，`quiet-startup@local` 扩展的监控名单已经**移除 DSH**（只剩 QQ / 微信，见 [10-quiet-autostart.md](10-quiet-autostart.md)）。否则你手动开客户端时，窗口会在登录后 5 分钟窗口期内被扩展收进托盘。

## 常用命令

```bash
# 后端状态 / 重启
systemctl --user status dsh-harness.service
systemctl --user restart dsh-harness.service

# 看日志
journalctl --user -u dsh-harness.service -b -f

# 临时完全切回桌面客户端（服务会被 dsh-client 自动停掉）
~/.local/bin/dsh-client

# 想恢复"开机启动客户端"：把文件挪回去即可
mv ~/.config/autostart-disabled/deepseek-harness-desktop.desktop ~/.config/autostart/
systemctl --user disable --now dsh-harness.service
```

## 验证

```bash
# 1) 服务在监听
curl -sI http://127.0.0.1:3080/ | head -1
ss -tlnp | grep 3080

# 2) 登录后应无客户端窗口，但托盘里也不再有 DSH 图标（客户端没启动，属预期）
pgrep -af deepseek-harness-desktop || echo "客户端未运行（符合预期）"

# 3) 点桌面/菜单里的「DeepSeek Harness（网页版）」，应直接在 Firefox 新窗口打开
```

## 注意 / 回滚

- **桌面客户端和 systemd 服务互斥**（都想占 3080）。要开客户端就用 `dsh-client`，它会先停服务。
- 桌面客户端设置里的「开机自启」如果被重新打开，会重新生成 `~/.config/autostart/deepseek-harness-desktop.desktop`，届时会和服务抢端口——保持它关闭。
- 无头服务跑的是同一个 profile，插件、插件配置、会话都在 `~/.dsh` 里，和客户端完全一致；只是 `dsh-tauri*` 这些桌面专用插件在无头模式下不起作用（不影响 Web UI）。
- 如果服务起不来：`dsh-web` 会自动回退到桌面客户端；也可以手动 `~/.local/bin/dsh-client`。
