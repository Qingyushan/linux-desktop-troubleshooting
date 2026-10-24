# 注销再登录后 Firefox 打不开：上个会话的残留进程锁着 profile

> 返回索引：[README](../README.md) ｜ 相关：[32-ubuntu-dock-double-click.md](32-ubuntu-dock-double-click.md)（同一次注销引发的另一件事）、[04-lx-music.md](04-lx-music.md)（同样涉及“进程还在但窗口没了”）

## 症状

注销再登录后点 Firefox，弹窗：

```
Firefox is already running, but is not responding. To use Firefox, you must
first close the existing Firefox process, restart your device, or use a different profile.
```

关掉弹窗再点，还是同一句；任务栏看不到任何 Firefox 窗口。

## 怎么定位

### 1. 先看进程，而不是先删锁

```bash
ps -eo pid,ppid,lstart,stat,args | grep -F '/snap/firefox/' | grep -v grep
```

当时的输出关键信息：

```
 6183  3573  六 10月 24 22:01:20 2026  Sl  /snap/firefox/8763/usr/lib/firefox/firefox --new-window http://127.0.0.1:3080
```

- 启动时间 **22:01:20**，而当前 `gnome-shell` 是 **22:04:27** 才启动的 → 这个 Firefox 属于**上一次登录**；
- `PPID=3573` 是 `systemd --user`，不是当前会话的进程。

### 2. 看 profile 锁指向谁

```bash
ls -l ~/snap/firefox/common/.mozilla/firefox/*/lock \
      ~/snap/firefox/common/.mozilla/firefox/*/.parentlock
```

期望输出（坏状态）：

```
lrwxrwxrwx ... lock -> 127.0.1.1:+6183
-rw-rw-r-- ... .parentlock      # 0 字节残留
```

锁里记的就是旧进程 pid。进程还在 → Firefox 认为“已有实例”，于是要求你先关掉它；但它的 Wayland 连接已经随会话结束而失效，永远不会响应。

### 3. 为什么注销没杀它

`loginctl show-user $USER -p Linger` 当时是 `no`，但进程仍被 `systemd --user` 接管（`PPID=3573`）。注销只结束图形会话，**不保证结束用户管理器下的进程**；snap 版 Firefox 尤其容易这样残留。

## 无效尝试（以及为什么）

- **只删 `lock` / `.parentlock`**：锁会立刻被重建，只要旧进程还在，等于没删；
- **`firefox --profile` 换 profile**：能起来，但丢登录态、丢会话，治标不治本；
- **等它自己退出**：失联的 Firefox 不会自己退出。

## 最终方案

### 手动（当场恢复）

```bash
kill -TERM <旧pid>          # 等 5 秒，确认进程消失
rm -f ~/snap/firefox/common/.mozilla/firefox/*/.parentlock
setsid /usr/bin/firefox >/tmp/ff-launch.log 2>&1 &
```

期望输出：

```bash
pgrep -x firefox | wc -l        # → 1（主进程）
ls -l .../lock                  # → 指向新的 pid
```

### 永久：登录时自动清理

脚本：[scripts/firefox-stale-cleanup](../scripts/firefox-stale-cleanup)（Python，无第三方依赖）

判定：**进程启动时间早于当前 `gnome-shell` 启动时间（留 1 秒容差）→ 上个会话残留**。

```bash
install -m 755 scripts/firefox-stale-cleanup ~/.local/bin/firefox-stale-cleanup
install -m 644 scripts/firefox-stale-cleanup.desktop \
               ~/.config/autostart/firefox-stale-cleanup.desktop
```

自启条目里是 `X-GNOME-Autostart-Delay=10`，等 `gnome-shell` 起来后再跑。

脚本行为：

1. 从 `/proc/*/comm` 找 `gnome-shell`，读 `/proc/<pid>/stat` 第 22 字段 `starttime` 换算成时间戳；
2. 遍历 `comm` 为 `firefox` / `firefox-bin` / `crashhelper` 的进程，比启动时间；
3. 先 `SIGTERM`，最多等 5 秒，仍未退出则 `SIGKILL`；
4. 确认没有 firefox 进程后，才删除 `lock` 与 `.parentlock`（避免误删正在使用的锁）；
5. 日志写 `/tmp/firefox-stale-cleanup.log`。

## 验证

```bash
~/.local/bin/firefox-stale-cleanup --dry-run
```

期望输出（当前会话没有残留时）：

```
[2026-10-24 22:11:26] gnome-shell 启动于 2026-10-24 22:04:28
[2026-10-24 22:11:26] 没有上个会话残留的 Firefox 进程，无需清理
```

人为构造“残留”验证识别逻辑（只打印不杀）：

```bash
~/.local/bin/firefox-stale-cleanup --dry-run --shell-start "$(date -d '+1 hour' +%s)"
```

期望输出：

```
发现 2 个上个会话残留进程: [16425, 16518]
  [dry-run] 将结束 pid 16425 (comm=firefox)
  [dry-run] 将结束 pid 16518 (comm=crashhelper)
```

## 代价与风险

| 项 | 说明 |
| --- | --- |
| 会不会误杀 | 正常使用的 Firefox 一定晚于 `gnome-shell` 启动，不会被选中；脚本只匹配三个固定进程名 |
| 找不到 shell 时 | 直接跳过，不做任何猜测 |
| 会话恢复 | 被结束的旧进程如果写过 sessionstore，新 Firefox 会提示“恢复上次会话”；没写过就丢 |
| 日志 | 每次运行追加到 `/tmp/firefox-stale-cleanup.log` |

## 回滚

```bash
rm ~/.config/autostart/firefox-stale-cleanup.desktop   # 停用自启
rm ~/.local/bin/firefox-stale-cleanup                  # 删除脚本
```

## 经验

1. **“already running”先查进程和启动时间，再碰锁文件**。锁是症状，残留进程才是病根。
2. **注销 ≠ 杀进程**：`PPID` 是 `systemd --user` 的应用可能活到下一次登录。
3. **清理脚本要能证明“什么时候不该动手”**：本例用“早于 `gnome-shell` 启动”做判据，并保留 `--dry-run` 与“找不到 shell 就跳过”。
