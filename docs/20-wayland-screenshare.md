# Wayland 下屏幕共享 / 录屏：为什么黑屏，以及怎么让它工作

> 返回索引：[README](../README.md) ｜ 相关：[19-audio-pipewire.md](19-audio-pipewire.md)（共享时带声音） ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 项 | 值 |
|---|---|
| 会话 | **Wayland**（`XDG_SESSION_TYPE=wayland`），GNOME 50 |
| Portal | `xdg-desktop-portal` **1.21.1**、`xdg-desktop-portal-gnome` **50.0**、`-gtk` 1.15.3 |
| 媒体 | PipeWire 1.6.2；GStreamer `pipewiresrc` **可用** |
| 已装工具 | 无 OBS、无 grim、无 gnome-screenshot |

---

## 1. 原理：Wayland 不给应用"直接读屏"的权限

X11 时代任何程序都能 `XGetImage` 抓全屏；Wayland 的合成器**不允许**应用直接读其他窗口的像素。于是有了标准链路：

```
应用（浏览器/OBS/会议软件）
   │ 1. 请求截图源
   ▼
xdg-desktop-portal ──► xdg-desktop-portal-gnome（弹"共享哪个屏幕/窗口"）
   │ 2. 用户选择
   ▼
PipeWire 节点（视频流）──► 应用读取
```

所以"黑屏/没有窗口列表"通常**不是应用坏了**，而是这条链上某一环没通：

- portal 服务没跑 / 崩溃；
- 应用用 X11 后端运行，却期望 Wayland 抓屏；
- 应用只支持老的 X11 抓屏方式（`XShm` / `XGetImage`），在 Wayland 下必然拿不到画面。

---

## 2. 定位顺序

### 第 1 步：确认你真的是 Wayland 会话

```bash
echo "$XDG_SESSION_TYPE"          # 期望：wayland
loginctl show-session $(loginctl | awk '/tty|seat/{print $1; exit}') -p Type
```

如果是 `x11`，那所有"Wayland 抓屏"教程都不适用，反过来也一样。

### 第 2 步：portal 是否在跑

```bash
systemctl --user status xdg-desktop-portal xdg-desktop-portal-gnome --no-pager | head -20
# 期望：active (running)

journalctl --user -b -u xdg-desktop-portal-gnome --no-pager | tail -30
```

常见报错：`Failed to create session`、`No such interface`、`permission denied`。

### 第 3 步：应用本身用的什么后端

| 应用 | 检查方式 | 期望 |
|---|---|---|
| Firefox | 地址栏 `about:support` → **Window Protocol** | `wayland` |
| Chrome / Chromium | 地址栏 `chrome://gpu` → Windowing | `Wayland`（老版本还需 `--enable-features=WebRTCPipeWireCapturer`） |
| Electron 应用 | `echo $ELECTRON_OZONE_PLATFORM_HINT` | `wayland` 或 auto |

X11 后端的应用（`Xwayland`）依然能"看到"自己的窗口，但**共享其他窗口/整个屏幕**会黑屏——这是设计使然，不是 bug。

### 第 4 步：共享时看有没有 PipeWire 节点

```bash
# 在"正在共享"的状态下执行
pw-cli ls Node | grep -i -A2 "screen\|capture"
# 或
wpctl status | sed -n '/Video/,$p'
```

有节点但应用还是黑屏 → 问题在应用侧（编解码/渲染）；没有节点 → 问题在 portal/选择器。

---

## 3. 修复动作

### 重启 portal（最快、最常有效）

```bash
systemctl --user restart xdg-desktop-portal-gnome
systemctl --user restart xdg-desktop-portal
# 然后重新发起共享（不是刷新页面就行，要重新点"共享"）
```

### 浏览器切到 Wayland 后端

- **Firefox（snap）**：默认已是 Wayland；若不是，退出后 `MOZ_ENABLE_WAYLAND=1 firefox`，并在 `about:support` 确认。
- **Chrome/Chromium**：确保从 Wayland 会话启动；老版本加 `--enable-features=WebRTCPipeWireCapturer`（新版本默认开）。
- 验证：`chrome://gpu` 里 `Windowing` 为 `Wayland`。

### 录屏工具怎么选

| 用途 | 推荐 | 说明 |
|---|---|---|
| 截一张图 | GNOME 内置（`PrintScreen`） | Wayland 下走 portal，最省事 |
| 录一段 | GNOME 内置（`Ctrl+Alt+Shift+R`） | 录的是整屏，不能选窗口 |
| 专业录制 | **OBS + PipeWire 源** | 必须用 "Screen Capture (PipeWire)"，不要用老的 X11 源 |
| 命令行 | `grim` **不适用** | grim 依赖 wlroots 协议，GNOME/Mutter 不支持 |

> 本机目前没装 OBS 和 grim。要装：`sudo apt install obs-studio`（装完仍需在 Wayland 会话里启动，OBS 才能看到 PipeWire 源）。

---

## 4. 无效尝试（踩过的坑）

- **装 `scrot` / `xwd` / `import`**：全是 X11 工具，在 Wayland 会话里要么报错要么抓到一片黑。
- **给浏览器加 `--disable-gpu`**：与抓屏无关，只会让渲染更慢。
- **改 `chrome://flags` 里的旧开关**：PipeWire 抓屏在新版本已默认启用，翻旧教程加 flag 反而可能冲突。
- **只刷新页面**：portal 会话是按"一次共享"授权的，刷新不会复用，必须重新点共享。

---

## 5. 速查

| 症状 | 最可能原因 | 先做 |
|---|---|---|
| 共享出来全黑 | 应用是 X11 后端 / portal 崩了 | 查 `about:support`、重启 portal |
| 选择器里没有窗口列表 | portal-gnome 没跑 | `systemctl --user status xdg-desktop-portal-gnome` |
| 只有鼠标指针在动 | 抓到了合成层但没抓内容 | 换 PipeWire 源 / 换应用后端 |
| 会议软件只给"整个屏幕" | 应用不支持窗口级捕获 | 属正常限制，用整屏 |
| 录出来没声音 | 音频源没选 | 见 [19](19-audio-pipewire.md)，OBS 里加音频采集 |

## 6. 经验

1. **先分清 X11 / Wayland**，再谈抓屏；这一条能省掉一半无效搜索。
2. **portal 是唯一合法入口**，"让应用直接读屏"的偏方在 Wayland 下不存在。
3. **重启 portal 比重启整个会话便宜得多**，值得先试。
4. **GNOME 内置截图/录屏已经够用**，装第三方工具前先确认它支持 PipeWire。
