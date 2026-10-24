# Ubuntu Dock 点击行为：单击预览、双击按状态收起/弹出（含三代补丁的坑）

> 返回索引：[README](../README.md) ｜ 相关：[33-firefox-stale-lock.md](33-firefox-stale-lock.md)（注销后残留 Firefox 锁 profile）、[10-quiet-autostart.md](10-quiet-autostart.md)（同样涉及 GNOME Shell 扩展）

## 想要的效果

| 应用状态 | 单击 Dock 图标 | 双击 Dock 图标 |
| --- | --- | --- |
| 多窗口，窗口可见 | 弹出**窗口预览列表** | **全部收回**（最小化） |
| 多窗口，全部已收回 | 弹出**窗口预览列表**，点哪个恢复哪个 | **全部弹出** |
| 单窗口，已聚焦 | 收回 | — |
| 单窗口，已收回 / 未聚焦 | 弹出该窗口 | — |

Ubuntu Dock 自带的 `click-action` 是**单一行为**，没有“双击动作”设置项，也没有“按窗口状态区分双击”的能力，所以必须改扩展代码。

## 为什么会反复翻车（三代补丁）

| 版本 | 做法 | 结果 |
| --- | --- | --- |
| v1 | 在最前面加 `event.get_click_count() > 1 → 最小化全部` | ❌ **单击也失效**：GNOME 50 的 `Clutter.get_current_event()` 没有 `get_click_count` 方法，`TypeError` 打断 `activate()` |
| v2 | 改用 `GLib.get_monotonic_time()` 记 `this._dshLastClick`，350ms 内两次即双击；单击延迟 300ms 弹预览 | ⚠️ 能跑，但把“全部收回状态”也当成“最小化全部”，双击无反应；且全部收回时单击只激活第一个窗口，不弹预览 |
| v3 | 先算 `allMinimized = windows.every(w => w.minimized)`，双击时按状态分别 `_activateAllWindows()` / `_minimizeWindow(true)`；单击多窗口一律延迟弹预览 | ✅ 当前版本 |

### v1 的根因（最坑的一个）

```bash
journalctl --user -b --no-pager | grep -i "JS ERROR"
```

期望输出（节选）：

```
JS ERROR: TypeError: event.get_click_count is not a function
    activate@file:///usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com/appIcons.js:631:53
```

`activate(button)` 里虽然写了 `const event = Clutter.get_current_event()`，但这个对象在当前 Shell 版本里**只有 `get_state()`，没有 `get_click_count()`**。原版代码里那处 `get_click_count()` 位于 `MINIMIZE` 分支，默认配置不会走到，所以上游没暴露。

教训：**别照着旧代码猜 API 存在**，先跑一次看 journal。

### v2 的问题

- 双击永远执行 `_minimizeWindow(true)`：窗口已经全部收回时，最小化没有任何效果 → “双击没用”；
- 全部收回时单击走的是 `this.focused === false` 分支 → 只激活第一个窗口，**不弹预览**。

需求实际是**状态相关**的，不是单一动作。

## 怎么定位（可复用）

### 1. 先确认 GNOME 到底加载了哪份扩展

```bash
gnome-extensions info ubuntu-dock@ubuntu.com
```

期望输出里有一行：

```
路径: /usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com
```

这说明**系统目录版本**在生效。GNOME 50 里，放到 `~/.local/share/gnome-shell/extensions/` 的同名副本**不会**覆盖系统版——我第一次改用户副本，改完看起来“没生效”，就是这个原因。

### 2. 看 Shell 的 JS 报错

```bash
journalctl --user -b --no-pager | grep -iE "JS ERROR|ubuntu-dock" | tail
```

任何 `TypeError` 都会让整个 `activate()` 提前退出，表现出来就是“单击没反应”。

### 3. 别指望热重载

```bash
gdbus call --session --dest org.gnome.Shell.Extensions \
  --object-path /org/gnome/Shell/Extensions \
  --method org.gnome.Shell.Extensions.ReloadExtension ubuntu-dock@ubuntu.com
```

期望输出（本机 GNOME 50.1）：

```
错误：GDBus.Error:org.freedesktop.DBus.Error.UnknownMethod: Method ReloadExtension is not implemented
```

结论：**Wayland 下改扩展只能注销重登**，`Alt+F2 → r` 也不可用。

## 最终方案

脚本：[scripts/ubuntu-dock-double-click.sh](../scripts/ubuntu-dock-double-click.sh)（幂等，自带备份与语法检查）

```bash
sudo scripts/ubuntu-dock-double-click.sh --dry-run   # 先检查扩展版本是否对得上
sudo scripts/ubuntu-dock-double-click.sh             # 应用 v3
```

期望输出：

```
首次运行：已保存原始备份 -> /usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com/appIcons.js.orig-ubuntu-dock
已写入 v3 补丁

语法检查：
  OK

下一步：注销 → 重新登录，然后：
  多窗口：单击 = 预览列表；双击 = 全部收回（可见时）/ 全部弹出（已收回时）
  单窗口：单击 = 收回（已聚焦）/ 弹出（已收回）
```

核心逻辑（`FOCUS_MINIMIZE_OR_PREVIEWS` 分支）：

```js
const allMinimized = windows.every(w => w.minimized);   // 是否全部收回
if (isDoubleClick) {                                    // 350ms 内两次左键
    if (allMinimized) this._activateAllWindows();       // 全部弹出
    else              this._minimizeWindow(true);       // 全部收回
} else if (windows.length > 1 || modifiers || button !== 1) {
    // 延迟 300ms 弹预览：既让单击可用，又给双击留判定窗口
} else if (this.focused) { this._minimizeWindow(); }     // 单窗口：收回
else { Main.activateWindow(windows[0]); }               // 单窗口：弹出
```

整个分支包在 `try/catch` 里，异常只退化为“激活窗口”，**不会再让单击失效**。

## 验证

1. 注销 → 重新登录（必须）；
2. 打开两个 Firefox 窗口（`Ctrl+N`）；
3. 单击 Dock 图标 → 出现窗口预览列表；
4. 双击 → 两个窗口全部收回；
5. 在全部收回状态下单击 → 出现预览列表，点某个窗口可单独恢复；
6. 在全部收回状态下双击 → 两个窗口全部弹出；
7. 若 Dock 消失或行为异常：

```bash
journalctl --user -b --no-pager | grep -iE "JS ERROR|ubuntu-dock" | tail
```

## 代价与限制

| 项 | 说明 |
| --- | --- |
| 单击延迟 | 多窗口预览延迟 **300ms** 才弹（给双击判定留时间）；嫌慢改脚本里的 `300` |
| 生效方式 | 必须注销重登；无法热重载 |
| 升级覆盖 | `apt upgrade gnome-shell-extension-ubuntu-dock` 会覆盖补丁，重跑脚本即可 |
| 系统文件 | 直接改 `/usr/share/...`，所以脚本必须 root；首次运行会留 `appIcons.js.orig-ubuntu-dock` |

## 回滚

```bash
sudo scripts/ubuntu-dock-double-click.sh --remove
```

或者手动：

```bash
sudo cp /usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com/appIcons.js.orig-ubuntu-dock \
        /usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com/appIcons.js
```

配合把行为改回 GNOME 原版：

```bash
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'focus-or-appspread'
```

注销重登后即恢复原样。

## 经验

1. **先确认“生效的是哪份文件”**：`gnome-extensions info` 的“路径”字段比目录结构更可信。
2. **扩展里报错 = 整个回调中断**：任何一行 `TypeError` 都会让单击完全没反应，先看 journal 再改代码。
3. **交互需求要按状态建模**：同一手势在不同窗口状态下含义不同（收回 vs 弹出），不要用一个固定动作覆盖。
4. **双击与单击共存需要延迟**：先弹预览再判双击必然打架，延迟 250–350ms 是折中。
