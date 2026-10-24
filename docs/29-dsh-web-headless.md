# DSH 日常用 Web 端：客户端托管 3080 + 网页快捷方式（开机不弹客户端窗口）

> 返回索引：[README](../README.md) ｜ 相关脚本：[dsh-web.sh](../scripts/dsh-web.sh)、[dsh-client.sh](../scripts/dsh-client.sh)、[install-dsh-launchers.sh](../scripts/install-dsh-launchers.sh)、[systemd/](../systemd/)

## 为什么要这么改

- DSH 桌面客户端是 Tauri + WebKitGTK。本机实测**不是软件渲染**（`nvidia-smi pmon` 里它是 NVIDIA graphics client，打开 renderD129、持有 dma-buf），但同一个 WebKit 引擎测「毛玻璃 + 动画」页面四种模式都只有 62 fps，说明瓶颈在**页面本身**（95 个客户端插件、0.9 MB 入口 JS、`backdrop-filter` 毛玻璃），而 Firefox 的 WebRender 处理这类负载明显更顺。
- 结论：**日常用独立浏览器打开 `http://127.0.0.1:3080`**，桌面客户端只在需要托盘/宠物时人工启动。2026-10-24 起按用户要求网页版启动器默认用 **Google Chrome** 打开（`CHROME_BIN` 可覆盖，改回 Firefox 只需设 `CHROME_BIN=/usr/bin/firefox`）。

于是要做两件事：

1. 后端改成**无头常驻**（跑 harness web 服务，不创建任何窗口）；
2. 加一个**网页快捷方式**，点一下就能在浏览器里打开（当前默认 Chrome；后端没起会自动拉起）。

> 仓库里对应的可复制实现：`scripts/install-dsh-launchers.sh`（一次装好 `dsh-web`、`dsh-client`、桌面入口与 systemd 单元）、`scripts/dsh-web.sh`、`scripts/dsh-client.sh`、`systemd/dsh-harness.service`、`systemd/dsh-appearance.service`。

## 改了哪些东西

| 文件 | 作用 |
| --- | --- |
| `~/.config/systemd/user/dsh-harness.service` | 登录时以 systemd user 服务启动 harness（profile `better-deepseek-harness-codex`，端口 3080），无窗口 |
| `~/.local/bin/dsh-web` | 打开 web 端：3080 通就直接开 Chrome（`CHROME_BIN` 可覆盖）；不通就先拉起桌面客户端，等最多 90 秒；还不行就通知失败 |
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

## 关闭桌面客户端的毛玻璃（blur）

客户端的「模糊」是 `~/.local/share/dsh-tauri/.store.dat` 里 `setting.appearance.blur`，属于**桌面客户端专有设置**，Web 端不生效（Web 端没有 Tauri 宿主推送外观）。

```bash
~/.local/bin/dsh-set-appearance --blur off      # 关模糊
~/.local/bin/dsh-set-appearance --blur on       # 开回来
~/.local/bin/dsh-set-appearance --opacity 100   # 顺带把侧栏不透明度调到 100
```

注意两点：

1. **客户端运行时会在退出时用内存里的值覆盖这个文件**，所以改了要等下次客户端启动才看得到效果；要立刻生效只能重启客户端（会中断正在用它托管的会话）。
2. 为了让设置不被覆盖，加了 `~/.config/systemd/user/dsh-appearance.service`（oneshot，登录时执行 `dsh-set-appearance --blur off`），每次登录都会把 blur 强制关掉。想恢复「客户端里自己改外观」的话：`systemctl --user disable dsh-appearance.service`。

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

# 3) 点桌面/菜单里的「DeepSeek Harness（网页版）」，应直接在 Chrome 新窗口打开
```

## 注意 / 回滚

- **桌面客户端和 systemd 服务互斥**（都想占 3080）。要开客户端就用 `dsh-client`，它会先停服务。
- 桌面客户端设置里的「开机自启」如果被重新打开，会重新生成 `~/.config/autostart/deepseek-harness-desktop.desktop`，届时会和服务抢端口——保持它关闭。
- 无头服务跑的是同一个 profile，插件、插件配置、会话都在 `~/.dsh` 里，和客户端完全一致；只是 `dsh-tauri*` 这些桌面专用插件在无头模式下不起作用（不影响 Web UI）。
- 如果服务起不来：`dsh-web` 会自动回退到桌面客户端；也可以手动 `~/.local/bin/dsh-client`。

## 2026-10-24 晚改版：改为「客户端托管、Web 端共用同一 3080」

起初做成 systemd 无头服务 + 桌面客户端按需启动，但**两者会抢 3080**：开客户端就得先停服务（会断开网页端会话）。用户要求“共用一个端口、不要 stop”，于是查了上游源码。

### 源码结论：客户端不能复用别人的 harness

- `service/workflow/launch.rs` 的 `start()` 只在 `has_owned_process()`（自己起的子进程还活着）时才跳过启动；
- `prepare_port()` 在非 Windows 分支：端口被**未知进程**占用时返回 `Ok(false)`，交给 `find_available_port()` 逐级 +1 → 客户端会在 **3081** 另起第二个 harness，和 systemd 服务共用同一个 `$DSH_HOME`（两个核心同时写存储，还有 `reset_active_profile_root` 会改 `cordis.yml`，很危险）。

所以“客户端附着到已有核心”在本版本不可行。

### 新方案（当前生效）

- **桌面客户端是 3080 的唯一宿主**：恢复开机自启（`auto_start=true` + `~/.config/autostart/deepseek-harness-desktop.desktop`），登录后由 `quiet-startup` 扩展把它最小化到托盘；
- **systemd 无头服务停用**（`systemctl --user disable dsh-harness.service`，单元文件保留备用）；
- `dsh-client` 只负责启动客户端，**不再 stop 任何服务**；
- `dsh-web`：3080 已通就直接开 Chrome；没通就先拉起桌面客户端，等最多 90 秒；
- `quiet-startup` 名单里重新加入 DSH（否则登录会弹客户端窗口）。

### 代价

- 客户端进程常驻（WebKit 子进程约 200–500 MB 内存），但窗口在托盘里，不参与日常交互；
- 关掉客户端＝断掉 Web 端后端，这是“单一宿主”的必然结果。

> 上游如果要支持“附着外部核心”，得让 `prepare_port` 在端口被占时先 `is_dsh_running(port)` 探测并复用；可以做为 feature request 提给 `dsh-tauri/deepseek-harness-desktop`。
