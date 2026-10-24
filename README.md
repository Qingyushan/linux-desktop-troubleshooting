# Ubuntu 26.04 + NVIDIA 桌面踩坑记录

> 记录时间：2026-10-23  
> 机器：Ubuntu 26.04.1 LTS / GNOME 50.1 (Wayland) / NVIDIA GTX 1060 Mobile (580.178.04) + Intel HD 630  
> 涉及：Firefox、Steam、QQ、微信、LX Music、DSH 桌面端（Tauri + WebKitGTK）

这份文档记录一次连续的桌面环境修复过程：从 GitHub 证书错误开始，到安装聊天/音乐/游戏软件，再到 **DSH 桌面端在 NVIDIA + WebKitGTK 下画面冻结** 和 **Dock / 应用菜单图标空白** 的排查。重点不是“最后哪个命令成功了”，而是**每一步是怎么判断的、哪些尝试被证明无效、哪些改动不该做**。

---

## TL;DR

1. **HTTPS 报错先查“谁在中间人”和“应用用哪个证书库”**。同一个根证书，系统信任了，Firefox / Steam 不一定信任。
2. **Firefox 用独立的 NSS 库**（`cert9.db`），系统 CA 与它无关；HSTS 站点没有“添加例外”。
3. **Steam 的内置浏览器 CEF 用 `~/.pki/nssdb`**，而且**新版 NSS 的 `certutil` 导入的条目，旧版 CEF 可能读不了**。用 NSS 3.98 的 `certutil` 重新导入可以修复。
4. **AppImage 与 deb 同版本也可能表现完全不同**。DSH 的 AppImage 换 deb 后渲染问题明显减少，先把“包”换掉，再调参数。
5. **“按钮能点、画面不动”不要默认是 GPU 画不出来**。这次软件渲染（llvmpipe + Skia CPU）仍然复现，说明问题在呈现/帧同步层，不是单纯光栅化。
6. **改启动器/环境变量后，一定用 `/proc/<pid>/environ` 验证真的生效**。本次多次出现“以为加了参数，实际启动路径没带上”的情况。
7. **清理时注意 `~/.local/bin` 的同名 wrapper 会遮蔽 `/usr/bin` 的可执行文件**，`command -v` 必须确认。
8. **全局 CSS / 主题补丁只能作为临时验证**，必须备份、可还原；应用更新会覆盖。
9. **桌面图标不显示，不一定是图标文件损坏**。GNOME Shell 会按应用/图标名缓存纹理；换一个**新的图标名 + 用户级 desktop 覆盖**，往往比反复覆盖同名文件更快生效。

> 配套记录：DSH 桌面端跑起来之后的**界面调优与插件去重**（显示缩放 125%、GNOME 应用网格密度、插件冗余清理、侧栏底部空按钮的根因）单独写在 [dsh-profile-tuning.md](dsh-profile-tuning.md)。

---

## 0. 环境

| 项 | 值 |
| - | - |
| 系统 | Ubuntu 26.04.1 LTS，kernel 7.0.0-38-generic |
| 桌面 | GNOME Shell 50.1，Wayland 会话 |
| GPU | NVIDIA GTX 1060 Mobile，驱动 580.178.04；Intel HD 630 核显 |
| WebKitGTK | 2.52.6-0ubuntu0.26.04.1 |
| 加速工具 | Steamcommunity_302 15.0.9（AppImage，HTTP/HTTPS 中间人 + hosts 重定向） |
| 浏览器 | Firefox 154（snap） |
| DSH | 桌面端 0.25.0；Harness 内核 0.2.1-rc.2 |
| 其它 | Steam 1.0.0.85、LX Music 2.12.6、QQ 3.2.32、微信 4.1.13.26 |

> 注意：下文很多问题都来自 **Steamcommunity_302（S302）**。它把 `github.com`、`store.steampowered.com` 等域名写进 `/etc/hosts` 指向 `127.0.0.1`，并在本机 443 端口用自签根证书做 TLS 中间人。系统证书库信任它，不代表每个应用都信任。

---

## 1. Firefox 打开 GitHub 报 `SEC_ERROR_UNKNOWN_ISSUER`

### 现象

- 仅 GitHub 打不开，其它站点正常；
- 页面提示证书颁发者未知，HSTS 站点无法添加例外；
- 系统时间正确，GitHub 本身没有故障。

### 根因

S302 把 `github.com` 指向 `127.0.0.1:443`，用自签根证书重签证书。该根证书已装进**系统**证书库（`/usr/local/share/ca-certificates/s302-*.crt`），但 Firefox 使用**自己的 NSS 库**（snap 版在 `~/snap/firefox/common/.mozilla/firefox/<profile>/cert9.db`），看不到系统证书。

### 修复

```bash
# 1. 找到 Firefox 配置目录（snap 与 deb 路径不同）
ls -d ~/snap/firefox/common/.mozilla/firefox/*/ 2>/dev/null
ls -d ~/.mozilla/firefox/*/ 2>/dev/null

P="$HOME/snap/firefox/common/.mozilla/firefox/<profile>"
CA=$(ls /usr/local/share/ca-certificates/s302-*-root-ca-*.crt | head -1)

# 2. 备份并导入
cp -a "$P/cert9.db" "$P/cert9.db.bak-$(date +%Y%m%d-%H%M%S)"
certutil -A -n "Steamcommunity302 Root" -t "C,," -i "$CA" -d sql:"$P"

# 3. 确认
certutil -L -d sql:"$P" | grep -i steam
```

**必须完全退出 Firefox 再启动**（NSS 库只在启动时加载）。如果 DSH/聊天页面在 Firefox 里，重启会中断，重新打开即可。

### 经验

- 不要用“关闭 HSTS”或 `security.enterprise_roots.enabled` 这类偏方；直接导入根证书最干净。
- 导入的是**根证书**，不是服务器叶子证书。
- 这种根证书具备解密 HTTPS 的能力，只应装在本机、只应信任可信工具；不要把该 CA 扩散到其它设备。

---

## 2. 安装 QQ、微信、Steam

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

## 3. Steam 商店 `Invalid SSL Certificate (error:-202 status:4)`

### 现象

Steam 客户端商店页显示：

```
Invalid SSL Certificate
The SSL certificate for https://store.steampowered.com/ is invalid ...
(error:-202 status:4)
```

系统 `curl` 访问同一地址返回 200，证书链校验通过。Firefox 也能正常打开。

### 根因

Steam 的 CEF（steamwebhelper）使用 **`~/.pki/nssdb`**，不是系统证书库。S302 已把根证书写进该库，但它是用 **NSS 3.120 的 certutil** 导入的。社区已知：新版 certutil 写出的条目，Steam 的旧版 CEF 读不了，表现为 `net_error -202`。

验证：

```bash
certutil -L -d sql:$HOME/.pki/nssdb          # 条目的确在，trust C,,
lsof -p <steamwebhelper_pid> | grep nssdb    # Steam 的确打开了 cert9.db
```

### 修复

用一个**旧版 NSS（3.98）**的 `certutil` 重新导入。不要降级系统 NSS，单独解包旧工具即可：

```bash
# 1. 下载 Ubuntu 24.04 的 NSS 工具（noble，3.98）
base=http://cn.archive.ubuntu.com/ubuntu
mkdir -p /tmp/nssold
for p in \
  pool/main/n/nss/libnss3_3.98-1build1_amd64.deb \
  pool/main/n/nss/libnss3-tools_3.98-1build1_amd64.deb \
  pool/main/n/nspr/libnspr4_4.35-1.1build1_amd64.deb; do
  f=$(basename "$p")
  curl -sSL -o "/tmp/$f" "$base/$p"
  dpkg-deb -x "/tmp/$f" /tmp/nssold
done

OLD="env LD_LIBRARY_PATH=/tmp/nssold/usr/lib/x86_64-linux-gnu /tmp/nssold/usr/bin/certutil"

# 2. 关掉 Steam，备份 NSS 库
/usr/games/steam -shutdown
cp -a ~/.pki/nssdb ~/.pki/nssdb.bak-$(date +%Y%m%d-%H%M%S)

# 3. 删除旧条目，用旧 certutil 重新导入
CA=$(ls /usr/local/share/ca-certificates/s302-*-root-ca-*.crt | head -1)
$OLD -D -d sql:$HOME/.pki/nssdb -n "S302 V15 Root CA d942d737f8373d1c" 2>/dev/null || true
$OLD -A -d sql:$HOME/.pki/nssdb -n "Steamcommunity302 Root" -t "C,," -i "$CA"

# 4. 用新 certutil 也要能读
certutil -L -d sql:$HOME/.pki/nssdb | grep -i steam
```

> 旧工具目录里同时带 `libnss3.so`、`libnspr4.so`，靠 `LD_LIBRARY_PATH` 隔离，不影响系统 NSS。

### 附：界面改中文

Steam 关闭时编辑 `~/.steam/registry.vdf`，把 `HKCU\Software\Valve\Steam\language` 和 `Steamsteamglobal\language` 改成 `schinese`，重启后 `steamwebhelper` 会带 `-lang=zh_CN`。也可以在 **设置 → 界面** 里改。

### 经验

- 先确认“证书链对不对”和“应用用哪个库”，再谈信任。
- `certutil` 不是“只要导入就行”，**版本兼容性真实存在**。
- 修改 Steam NSS 库前备份；Steam 更新/重装 S302 后可能复发，保留一键修复脚本。

---

## 4. LX Music 与自定义音源

### 安装

官方 GitHub Release 的 deb（2.12.6），装完菜单出现 **LX Music**。

### 自定义源的存储格式（重点）

LX Music 的“自定义源”不是放在 `sources/` 目录，而是存在：

```
~/.config/lx-music-desktop/LxDatas/user_api.json
```

结构：

```json
{
  "userApis": [
    {
      "id": "user_api_xxx_<timestamp>",
      "name": "星海音乐源",
      "description": "...",
      "author": "...",
      "homepage": "...",
      "version": "v3.2.15",
      "allowShowUpdateAlert": false,
      "script": "gz_<base64(zlib(script))>"
    }
  ]
}
```

- `script` 是 `zlib.deflate` 后 base64，前缀 `gz_`；
- 当前启用的源写在 `LxData/config_v2.json` 的 `setting["common.apiSource"]`；
- 源脚本必须以 `/* ... @name ... */` 块注释开头，应用会解析 `@name/@version/@author/@homepage`；
- 成功加载时主进程日志会出现 `load api <名字>`，并创建一个隐藏的 **User api** WebKit 窗口。

### 本次加载的源

来自公开仓库 [pdone/lx-music-source](https://github.com/pdone/lx-music-source)：

- 星海音乐源 v3.2.15（网易/QQ/酷狗/酷我/咪咕/汽水，musicUrl + lyric + pic）
- 全豆要聚合音源 v9.3（多链路回退）
- 幻音音源 v3

### 风险提示

- 这些是第三方脚本，以应用权限运行、会访问第三方接口；安装前应检查是否为明文、有无 `eval/require/fs/child_process` 等可疑调用（本次三个源均为明文，未发现明显问题）。
- 音源依赖的接口随时可能失效；曲库版权归各平台，请仅作试听并支持正版。
- 应用更新可能覆盖 profile，来源失效后需重新导入。

---

## 5. DSH 桌面端画面冻结（本次最耗时的问题）

### 现象

- 页面能正常显示第一帧，之后**只有拖动窗口边缘（resize）时才刷新**；
- 按钮、输入框都能交互，状态也在变，但画面停在上一帧；
- 打开设置菜单时尤其容易“卡死”；
- AppImage 与 deb 都出现过，deb 明显轻很多。

### 环境特征

- Tauri + WebKitGTK 2.52.6；
- NVIDIA 580 驱动 + XWayland（应用设置 `force_xwayland: true`）；
- 软件渲染（llvmpipe + `WEBKIT_SKIA_ENABLE_CPU_RENDERING=1`）**仍然复现**。

> 上游跟踪：#789 / #791 已解释 AppImage 的 GTK 钩子强制 XWayland；本机 deb + `force_xwayland` 的补充报告见 [#1226](https://github.com/dsh-tauri/deepseek-harness-desktop/issues/1226)。

### 试错矩阵

| # | 尝试 | 结果 | 说明 |
| - | - | - | - |
| 1 | `WEBKIT_DISABLE_DMABUF_RENDERER=1` | 无效 | 排除 DMA-BUF 花屏类问题，但不是本症状 |
| 2 | `WEBKIT_DISABLE_COMPOSITING_MODE=1` | 无效 | 关闭加速合成也不恢复持续刷新 |
| 3 | 1+2 组合 | 无效 | 最“重”的组合也不行 |
| 4 | `WEBKIT_FORCE_VBLANK_TIMER=1` | 无效 | 强制定时器帧同步也不行 |
| 5 | 1+2+4 组合 | 无效 | 本次 AppImage 的最终尝试 |
| 6 | 软件渲染（`LIBGL_ALWAYS_SOFTWARE=1` + `WEBKIT_SKIA_ENABLE_CPU_RENDERING=1`） | 无效 | **关键结论：不是 GPU 光栅化问题** |
| 7 | 全局 `backdrop-filter: none` + 主题菜单模糊补丁 | 无效 | 排除 CSS 毛玻璃拖垮合成器 |
| 8 | 关闭宠物窗口、窗口模糊/半透明 | 无效 | 排除 Tauri 窗口特效 |
| 9 | X11 / Wayland 原生切换 | 无效 | 排除单一后端 |
| 10 | 换 **.deb**（同版本 0.25.0） | **明显改善** | 同版本不同打包，表现不同 |

### 根因判断（诚实版）

未能 100% 定位到 WebKit 内部的具体 bug。可以确定的是：

- 不是“画不出来”（软件渲染仍能画第一帧）；
- 不是单纯 DMA-BUF / 加速合成；
- 更像是 **WebKitGTK UI 进程的帧呈现/帧同步在 NVIDIA + XWayland 组合下停摆**，resize 强制触发一次 present；
- AppImage 与 deb 的差异（运行时、环境、启动方式）会放大或掩盖这个问题。

### 有效的工程做法

1. **先换包**：AppImage → deb，成本最低、收益最大。
2. 保留“按症状加参数”的能力，而不是一次性全上：
   - 花屏/黑屏/闪烁 → `WEBKIT_DISABLE_DMABUF_RENDERER=1`
   - 只有 resize 刷新 → `WEBKIT_FORCE_VBLANK_TIMER=1`
   - 崩溃/静默退出 → 最后才 `WEBKIT_DISABLE_COMPOSITING_MODE=1`
3. 每次只加一个变量，并在重启后检查：

```bash
pid=$(pgrep -f '^/usr/bin/deepseek-harness-desktop$')
tr '\0' '\n' < /proc/$pid/environ | grep WEBKIT
```

4. 不要相信“应用内重启”会带上新环境；它通常 `exec` 自身，环境还是旧的。
5. 不要用全局 CSS/主题补丁长期兜底；验证完要还原。

### 性能代价（重要）

| 变量 | 代价 | 建议 |
| - | - | - |
| `WEBKIT_DISABLE_COMPOSITING_MODE=1` | **最大**：滚动/动画/视频/Canvas 全部 CPU 光栅化，CPU 与耗电上升，动画不顺滑 | 非必要不用 |
| `WEBKIT_DISABLE_DMABUF_RENDERER=1` | 中等：共享内存多一次拷贝，视频/动画有开销 | 只在花屏/黑屏时用 |
| `WEBKIT_FORCE_VBLANK_TIMER=1` | 很小：定时器代替 DRM vblank，可能轻微帧抖动 | 只在 resize 刷新时用 |

---

## 5.1 DSH 停靠栏 / 应用菜单图标空白

> 上游报告：[dsh-tauri/deepseek-harness-desktop#1227](https://github.com/dsh-tauri/deepseek-harness-desktop/issues/1227)

### 现象

- deb 版 DSH 启动后，左侧 Dock 只有运行小圆点，图标槽位是空的；
- Super 打开应用菜单，`DSH Tauri` 也是空白方块，只剩右上角绿色通知角标“1”和文字；
- 应用本身、窗口标题、`dsh://` 关联都正常，说明不是程序起不来。

### 诊断

先看窗口本身有没有图标：

```bash
xprop -id <DSH 窗口 id> _NET_WM_ICON WM_CLASS
```

本次结果：

```text
_NET_WM_ICON(CARDINAL) =       # 属性为空，没有任何像素数据
WM_CLASS = "deepseek-harness-desktop", "Deepseek-harness-desktop"
```

再确认桌面文件和图标资源：

```bash
grep -E '^(Name|Icon|StartupWMClass)=' "/usr/share/applications/DSH Tauri.desktop"
find /usr/share/icons/hicolor -name 'deepseek-harness-desktop.png'
```

图标文件是存在的，`Icon=deepseek-harness-desktop` 也能被 GTK / St 的图标主题解析。问题不在“文件损坏”，而在 **Shell 对这个应用的图标纹理缓存 / 窗口关联**：

- X11 窗口的 `_NET_WM_ICON` 为空，Dock 对运行中的窗口可能优先使用窗口图标；
- 应用菜单使用 desktop entry 的图标；同名图标曾经加载失败后，Shell 可能一直复用空白纹理；
- 只覆盖同名 PNG 往往不生效，因为纹理缓存 key 是 **GIcon 字符串 + 尺寸 + 缩放 + 样式**，不是文件 mtime。

### 修复

核心思路：**换一个新的图标名 + 用户级 desktop 覆盖**，让 Shell 用一个全新的缓存 key；Dock 侧再用 `_NET_WM_ICON` 兜底。

```bash
# 1. 生成一套“新名字”的用户图标（不碰 /usr/share，避免升级覆盖和权限问题）
for s in 32x32 128x128 256x256@2 512x512; do
  install -Dm644 \
    "/usr/share/icons/hicolor/$s/apps/deepseek-harness-desktop.png" \
    "$HOME/.local/share/icons/hicolor/$s/apps/deepseek-harness-desktop-visible.png"
done

# 2. 用户级 desktop 覆盖，Icon 指向新文件，StartupWMClass 保持和 WM_CLASS 一致
mkdir -p "$HOME/.local/share/applications"
cp -a "/usr/share/applications/DSH Tauri.desktop" \
      "$HOME/.local/share/applications/DSH Tauri.desktop"
sed -i "s|^Icon=.*|Icon=$HOME/.local/share/icons/hicolor/512x512/apps/deepseek-harness-desktop-visible.png|" \
      "$HOME/.local/share/applications/DSH Tauri.desktop"

# 3. 刷新 desktop 数据库和用户图标缓存
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# 4. 完全退出 DSH 再启动（不能只关窗口）
pkill -f '^/usr/bin/deepseek-harness-desktop$' || true
```

启动后确认 desktop entry 解析到新图标：

```bash
gjs -c 'const Gio=imports.gi.Gio; print(Gio.DesktopAppInfo.new("DSH Tauri.desktop").get_icon().to_string())'
```

如果 **Dock 仍然空白、应用菜单已正常**，说明窗口自带的 `_NET_WM_ICON` 为空是最后一块短板。可以对当前窗口设置 64×64 图标（临时，窗口关闭即失效，仅用于确认）：

```bash
python3 - <<'PY'
import ctypes
from PIL import Image

# 换成实际的 DSH 主窗口 id；xwininfo -root -tree | grep 'DSH Tauri'
wid = 0xc00003
src = "/usr/share/icons/hicolor/128x128/apps/deepseek-harness-desktop.png"
im = Image.open(src).convert("RGBA").resize((64, 64), Image.LANCZOS)
data = [64, 64]  # 前两个元素是宽、高
for r, g, b, a in im.getdata():
    data.append(a << 24 | r << 16 | g << 8 | b)

x11 = ctypes.cdll.LoadLibrary("libX11.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
dpy = x11.XOpenDisplay(None)
atom = x11.XInternAtom(ctypes.c_void_p(dpy), b"_NET_WM_ICON", False)
arr = (ctypes.c_ulong * len(data))(*data)
x11.XChangeProperty(ctypes.c_void_p(dpy), ctypes.c_ulong(wid), ctypes.c_ulong(atom),
                    ctypes.c_ulong(6), 32, 0, arr, len(data))
x11.XFlush(ctypes.c_void_p(dpy))
PY
```

> 上面这段是“确认问题”的临时手段，不应作为长期方案。真正持久的是第 1–3 步的用户级 desktop + 新图标名；窗口级图标只影响当前 X11 窗口。

### 结果与边界

- 本次操作后，Dock 和应用菜单的图标都恢复；
- 用户级 `.desktop` 覆盖和用户图标目录是持久的，重装/升级应用只要不删除 `~/.local/share/applications/DSH Tauri.desktop` 就仍然有效；
- 如果应用更新后菜单又变回空白，先检查覆盖文件是否被删除、`StartupWMClass` 是否仍匹配，再重跑脚本；
- 不要用 `sudo gtk-update-icon-cache /usr/share/icons/hicolor` 之类的方式硬刷系统缓存；用户级覆盖更安全，也不会在包升级时被覆盖。

### 经验

- 图标“文件存在”不等于“Shell 会显示”：缓存 key、desktop entry、窗口关联是三层不同的问题。
- `_NET_WM_ICON` 为空是 Dock 空白的强信号；`WM_CLASS` 的大小写和 `StartupWMClass` 必须对得上。
- 换图标名比反复覆盖同名文件可靠，因为 Shell 的纹理缓存按 GIcon 字符串做 key。
- 用户级 desktop 覆盖（`~/.local/share/applications`）优先于 `/usr/share/applications`，适合做这种“不碰系统文件”的修复。

---

## 6. 切换到 .deb 与清理

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

## 7. 功能体检（deb 版）

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

## 8. 经验清单

1. **HTTPS 问题先画信任链地图**：系统 CA、Firefox NSS、Chrome/CEF NSS、应用自带 CA，各是各的。
2. **HSTS 站点不要指望“忽略警告”**；要么信任根证书，要么换路径。
3. **`certutil` 版本会影响兼容性**；必要时用旧 NSS 的独立二进制，不要降级系统库。
4. **改动启动方式后验证 `/proc/<pid>/environ`**，不要只看 `.desktop` 文件。
5. **应用内“重启”通常不重新读环境变量**；要完全退出再启动。
6. **同版本不同打包可能行为不同**；先换包，再调参。
7. **软件渲染仍复现 → 不要继续在 GPU 光栅化上打转**，查呈现/帧同步。
8. **一次只改一个变量**，并记录结果；本次试错矩阵就是靠这个避免“全上但不知道哪个有用”。
9. **全局 CSS/主题补丁必须可还原**，且应用更新会覆盖；不要把它当长期方案。
10. **清理时先 `command -v`**，防止 `~/.local/bin` 的 wrapper 遮蔽 `/usr/bin`。
11. **保留用户数据**（`~/.dsh`、`~/.local/share/dsh-tauri`），只删可再生的启动器和缓存。
12. **inotify 上限**是 DSH 日志明确建议的稳定性修复；大量文件监听场景容易触发 ENOSPC。
13. **插件安装失败要看 pnpm 的 build-script 策略**；`ERR_PNPM_IGNORED_BUILDS` 会让整条安装命令失败。
14. **不要把 MITM 根证书扩散**；它是本机排障工具，不是“系统必备证书”。
15. **所有操作留备份**：`cert9.db`、`~/.pki/nssdb`、`.store.dat`、profile 的 `package.json`。
16. **图标空白先分层**：`_NET_WM_ICON`（窗口）→ desktop entry / `StartupWMClass`（关联）→ GIcon 纹理缓存（Shell）；换新图标名通常比覆盖同名文件更快生效。

---

## 9. 可复用脚本

见 `scripts/`：

- `fix-firefox-s302-ca.sh`：把 S302 根证书导入 Firefox NSS 库（自动找 snap/deb 配置目录）。
- `fix-steam-s302-ca.sh`：用 NSS 3.98 的 certutil 重新导入 Steam 的 `~/.pki/nssdb`。
- `fix-dsh-icon.sh`：为 DSH 生成新名字的用户图标并写入用户级 desktop 覆盖，修复 Dock / 应用菜单空白图标（不碰 `/usr/share`，可重复执行）。
- `install-quiet-startup.sh`：安装 `quiet-startup@local` 扩展 + 3 个 autostart 入口，让 QQ / 微信 / DSH 登录后安静启动（窗口最小化到托盘）；源码在 `gnome-extension/`。
- `fix-steam-ntfs-library.sh`：把 Steam 库路径对齐到开机挂载点、清掉同一块 NTFS 盘的重复挂载，修「兼容性工具失败」的复发根源。

> 使用前先读脚本；都会先备份。

---

## 10. 附录：常用检查命令

```bash
# 当前应用环境（确认参数是否生效）
pid=$(pgrep -f '^/usr/bin/deepseek-harness-desktop$')
tr '\0' '\n' < /proc/$pid/environ | grep -E 'WEBKIT|GDK|LIBGL'

# WebKit 进程
ps -eo pid,rss,cmd | grep -E 'WebKit(Web|Network)Process'

# 窗口（XWayland 下）
xwininfo -root -tree | grep -iE 'DSH Tauri|Pet'

# 服务与端口
ss -tlnp | grep 3080

# 证书链
openssl s_client -connect store.steampowered.com:443 -servername store.steampowered.com </dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# NSS 库
certutil -L -d sql:$HOME/.pki/nssdb
certutil -L -d sql:$HOME/snap/firefox/common/.mozilla/firefox/<profile>

# DSH 日志
tail -50 ~/.local/share/dsh-tauri/logs/desktop.log
grep -iE 'error|fail|warn' ~/.local/share/dsh-tauri/logs/desktop.log | tail

# 插件
cat ~/.local/share/dsh-tauri/plugin-errors.json
dsh --profile tauri --dump-config | grep -i <plugin>
```

---

## 11. 尚未解决 / 后续

- DSH 的渲染问题只做到“deb 明显改善”，没有定位到 WebKit 的具体 bug；如果再次出现“仅 resize 刷新”，优先试 `WEBKIT_FORCE_VBLANK_TIMER=1`，并记录 WebKitGTK 版本。
- 7 个外部插件仍未挂载；需要在应用内重新启用，或重跑安装并确认 `dsh.profile.bundles`。
- Office 运行时未初始化，启用 office-kit 后首次使用会 bootstrap；如失败再手动跑 `postinstall.mjs`。
- 更新检查的 GitHub API 301 未处理；属于应用侧问题。

---

## 12. 好用的玩法技巧（日常使用）

这一节不是排障，而是把这次装好的软件调成“顺手”的配置。按软件分开，命令都可以直接复制。

### 12.1 Rime 雾凇拼音：输入法调顺手

- 切换：`Super+Space` 在“中文键盘 / Rime”之间切；`Shift` 临时中英；`1-9` 选候选，空格上屏，`Esc` 取消。
- 配置目录：`~/.config/ibus/rime`。改完配置后执行：

  ```bash
  rime_deployer --build ~/.config/ibus/rime
  ibus-daemon -drx
  ```

- 自定义短语：编辑 `~/.config/ibus/rime/custom_phrase.txt`，每行 `词<Tab>拼音<Tab>权重`：

  ```text
  深度求索	shen du qiu suo	100
  ```

  保存后重新 deploy，输入 `shendu` 之类就能看到。拼音用空格分音节，不要写声调；权重越大越靠前。

- 换回旧配置：

  ```bash
  rm -rf ~/.config/ibus/rime
  mv ~/.config/ibus/rime.bak-20261023-203129 ~/.config/ibus/rime
  ibus-daemon -drx
  ```

- 候选框不出现：先确认 `ibus engine` 输出 `rime`；再注销重登，或 `ibus-daemon -drx`。

### 12.2 Variety：壁纸轮换不折腾

- 打开 Variety，在 **Sources** 里添加本地壁纸文件夹；在线源可按需启用 Bing / Unsplash。
- 在 **Preferences** 里设置切换间隔；NVIDIA 机器如果切换动画卡顿，关闭特效或选“无效果”。
- 想让壁纸登录后自动轮换，在 Preferences 勾选开机启动；不想自启就取消。
- 命令行快捷操作：

  ```bash
  variety --set /home/qys/图片/wallpaper.jpg   # 立刻设置某张
  variety --next          # 下一张
  variety --pause         # 暂停轮换
  variety --preferences   # 打开设置
  ```

- 在线源下载的图在 `~/.config/variety/Downloaded`；想离线就只用本地文件夹。

### 12.3 QQ / 微信 / DSH 开机「安静」自启（窗口最小化，托盘常驻）

目标：登录后三个应用自己起来，但**主窗口不弹出来抢焦点**，托盘里能看到图标，点一下就回来。

**难点**：QQ、微信 4.x、DSH 桌面端现在都是原生 Wayland 窗口；Wayland 没有"让外部进程最小化别人窗口"的接口（`xdotool` / `wmctrl` 只对 XWayland 窗口有效），所以没法靠"启动后再把窗口藏起来"的脚本。唯一能做这件事的是**跑在 GNOME Shell 进程里的扩展**。

**做法**：一个本地小扩展 `quiet-startup@local` + 三个 autostart 入口。

- 登录后 150 秒内，**每 500ms 扫描全部窗口**，命中名单就 `minimize()`；
- 命中判定有两条路（缺一不可，原因见下面的复盘）：
  1. 窗口名：`wm_class` / `app_id`，精确比对 + 长标识（≥4 字符）包含匹配；
  2. 进程兜底：`win.get_pid()` → 读 `/proc/<pid>/cmdline`，命中 `/opt/qq/qq`、`wechat`、`deepseek-harness-desktop`；
- 首次命中即使窗口带着焦点也压下去（登录时 autostart 窗口通常自带焦点）；之后应用自己把窗口弹回来才重压，最多 3 次，且窗口有焦点（你正在用）就让位；
- 150 秒后彻底放手，之后手动开这些应用、开新的聊天窗口都不受影响。

安装（幂等，可重复执行）：

```bash
./scripts/install-quiet-startup.sh
```

| 路径 | 作用 |
| --- | --- |
| `~/.local/share/gnome-shell/extensions/quiet-startup@local/` | 扩展本体（源码在仓库 `gnome-extension/`） |
| `~/.config/quiet-startup/config.json` | 窗口期秒数、重试次数、窗口名列表 `apps`、进程兜底列表 `processes` |
| `~/.config/autostart/{wechat,qq,deepseek-harness-desktop}.desktop` | 自启入口，延迟 8 / 12 / 5 秒 |
| dconf `org.gnome.shell enabled-extensions` | 启用扩展（保留已有的其它扩展） |

**必须注销重登一次**：GNOME Shell 只在自己的启动流程里扫描扩展目录，运行期新加的扩展不会被发现（此时 `gnome-extensions enable` 会报"扩展不存在"，不是配置错了）。

重登后验证：

```bash
gnome-extensions info quiet-startup@local    # State 应为 ENABLED
cat /tmp/quiet-startup.log
```

正常的日志长这样（`app=` 是窗口名命中，`process=` 是 pid 兜底命中，两种都算成功）：

```
== enable: apps=deepseek-harness-desktop,qq,wechat,... procs=/opt/qq/qq,wechat,... window=150s
existing windows: pid=0 names=-
created: pid=4094 names=qq
minimize(created#1): app=qq pid=4094 names=qq
created: pid=4156 names=-
minimize(scan#1): process=wechat pid=4156 names=wechat
```

> 想验证"现在就行"而不重登，可以看 `existing windows:` 那一行：它会把当前所有窗口的 pid 和名字打出来。

托盘图标：QQ / DSH 走 SNI，由 Ubuntu 自带的 AppIndicator 扩展显示；微信 4.x 内置 SNI 支持，登录后出现在托盘（未登录时只有登录窗口，托盘还没建）。

名单不对（某个应用还是弹窗）时：看日志 `created:` 后面的名字，加进 `config.json` 的 `apps` 数组，再

```bash
gnome-extensions disable quiet-startup@local && gnome-extensions enable quiet-startup@local
```

（改配置不用重登，改 `extension.js` 代码才需要重登。）

取消：

```bash
gnome-extensions disable quiet-startup@local          # 只停"最小化"，自启保留
sed -i 's/^X-GNOME-Autostart-enabled=true/X-GNOME-Autostart-enabled=false/' \
    ~/.config/autostart/{wechat,qq,deepseek-harness-desktop}.desktop   # 连自启一起停
```

**复盘：第一版为什么没生效**

第一版只在 `window-created` 时按窗口名匹配一次，结果重启后 QQ 被最小化了、微信和 DSH 没有。日志说明了原因：

```
[12:01:59] created: qq
[12:01:59] minimize(created#1): app=qq names=qq        <- XWayland，创建时就有 WM_CLASS
[12:02:00] created: (no name)                          <- 原生 Wayland，创建时 app_id 还没提交
[12:02:00] created: (no name)
```

同一批窗口在几十毫秒后（重新 enable 时打印的 `existing windows:`）名字就变成了 `qq` / `wechat` / `deepseek-harness-desktop`。也就是说 **`app_id` 是在 `window-created` 之后才提交的**，一次性匹配必然漏掉原生 Wayland 窗口。所以改成"持续扫描 + 进程 pid 兜底"：即使 `app_id` 永远为空的窗口，也能靠 `/proc/<pid>/cmdline` 认出来。

**踩过的坑**：

- 旧 AppImage 时代留下的 `~/.config/autostart/Deepseek Harness Desktop.desktop` 是重复入口，会让 DSH 被拉起两次（第二次激活还会把刚最小化的窗口顶回来）；已挪到 `~/.config/autostart-disabled/`。
- 别为了"藏窗口"去开 `force_xwayland=true` 或 `GDK_BACKEND=x11`：那等于把 DSH 整个会话换回 XWayland，可能把第 5 节的"只有 resize 才刷新"重新引回来。
- 别用 `xdotool windowunmap` 硬藏窗口：应用会以为自己仍然可见，之后的焦点/输入行为会变得很怪；`minimize()` 才是正常路径。
- 微信/QQ 如果没有自动登录，第一次出现的**登录窗口也会被最小化**：点 Dock 图标或托盘菜单里的"显示主面板"即可。
- 自启入口里带 `X-GNOME-Autostart-Delay` 是为了错开登录瞬间的 IO；DSH 自己设置里的"开机自启"如果被重开，可能把 `Exec` 改回不带延迟的原始命令——窗口仍然会被扩展最小化，不影响结果。
- 改完 `extension.js` **必须重新登录**才生效：GNOME 45+ 用 ESM 加载扩展，`gnome-extensions disable/enable` 会复用模块缓存，改了代码也不会重新读（实测日志里还是旧格式）。改 `config.json` 则只需 disable/enable。
- 别用"窗口有焦点就不压"当作首次命中的条件：autostart 的窗口本来就会拿焦点，加了这条等于一个都不压。正确做法是首次命中照压、只在"用户还原后"让位。

### 12.4 Steam + S302：先开 S302，再开 Steam

- S302 不在运行时，`/etc/hosts` 里指向 `127.0.0.1` 的域名会“连接被拒绝”；先启动 S302，再开 Steam / 浏览器。
- Steam 商店证书报 `-202` 时，跑仓库里的 `scripts/fix-steam-s302-ca.sh`；Firefox 报 `SEC_ERROR_UNKNOWN_ISSUER` 时跑 `scripts/fix-firefox-s302-ca.sh`。
- Steam 更新 / 重装后证书可能复发，脚本可以重复跑；跑之前会备份 NSS 库。
- 界面语言：Steam 设置 → 界面 → 简体中文；或者关闭 Steam 后改 `~/.steam/registry.vdf` 的 `language` 为 `schinese`。

#### 12.4.1 启动游戏报「兼容性工具失败」

现象：点「开始游戏」立刻弹窗 `启动此游戏时发生错误：兼容性工具失败`，游戏根本没起来（本次是《米塔 MiSide》，Windows 游戏，走 Proton Experimental）。

**日志先看 `compat_log.txt`**，一行就能定性：

```bash
grep -nE "unsupported version|Loaded manifest|StartSession" ~/.steam/steam/logs/compat_log.txt | tail
```

本次的关键行：

```
[12:35:22] Registering tool proton_experimental, AppID 1493710
[12:35:22] Registering tool steamlinuxruntime_4, AppID 4183110
   # ← 注意：这次启动没有 "Loaded manifest for tool ..." 行
[12:37:57] Tool 1493710 "Proton Experimental" unsupported version 0.
```

**根因**：不是游戏坏了，也不是 Proton 文件坏了 —— 是 Steam 这次启动时**没读到** Proton / Steam Linux Runtime 的 `toolmanifest.vdf`，于是把这些兼容性工具登记成 `version 0`，之后任何启动请求都被拒。重启 Steam 后同一批工具正常打印 `Loaded manifest for tool 1493710.`，错误消失，游戏能进。

**修复（一条重启就够）**：

```bash
~/.steam/debian-installation/steam.sh -shutdown
nohup setsid ~/.steam/debian-installation/steam.sh >/dev/null 2>&1 &
# 40 秒后确认工具清单读到了：
grep "Loaded manifest for tool 1493710" ~/.steam/steam/logs/compat_log.txt | tail -1
```

**为什么读不到 / 怎么防复发**：本机 Steam 库在 NTFS 盘（`/dev/sda2`，ntfs3）上，Proton 和 Steam Linux Runtime 也躺在这块盘里。同一块盘当时还被 `fstab`（`/mnt/G1`）和 `udisks`（`/run/media/qys/G1`）**各挂了一份**，Steam 用的是 `/run/media/...` 这条随时可能消失的路径。做法：

```bash
./scripts/fix-steam-ntfs-library.sh --dry-run   # 先看会改什么
./scripts/fix-steam-ntfs-library.sh             # 对齐库路径到 /mnt/G1，卸掉重复挂载，重启 Steam
```

> 会关掉 Steam（游戏会退出），跑之前先存档。

**顺手能做的自检**：

```bash
# 容器本身是否健康（只跑 /usr/bin/true，不动游戏）
"/run/media/qys/G1/SteamLibrary/steamapps/common/SteamLinuxRuntime_4/_v2-entry-point" \
  --verb=run -- /usr/bin/true && echo "SLR4 OK"
# Proton 官方的说法：工具"损坏或不完整"时先验证完整性，并避开非 Linux 原生文件系统
# https://github.com/ValveSoftware/steam-for-linux/issues/12655
```

**长期建议**：NTFS 上的 Steam 库能跑（本次 Wine 前缀就建在 NTFS 上，372 MB，游戏正常启动），但 Valve 明确只支持 Linux 原生文件系统。Proton 游戏一多、或再来一次「兼容性工具失败」，把库迁到 ext4 分区是最省心的。

### 12.5 LX Music：音源先备份，再折腾

- 自定义源在 `~/.config/lx-music-desktop/LxDatas/user_api.json`，升级 / 重装前先备份：

  ```bash
  cp ~/.config/lx-music-desktop/LxDatas/user_api.json \
     ~/lx-user-api-backup-$(date +%F).json
  ```

- 换源后如果没声音，先看主进程日志有没有 `load api <名字>`；没有就重新导入。
- 第三方音源可能失效、可能带风险；只试用，支持正版。

### 12.6 DSH 桌面端：优先 deb，少改全局

- 优先用 `.deb` 版；AppImage 的 GTK 钩子会强制 `GDK_BACKEND=x11`，在 NVIDIA + Wayland 上更容易触发“只有 resize 才刷新”。
- 出现停绘时，临时拖一下窗口边缘能刷新，但这只是绕过；长期用 `WEBKIT_FORCE_VBLANK_TIMER=1` 启动，或参考第 5 节。
- 图标空白时跑 `scripts/fix-dsh-icon.sh`；不要再全局改 `~/.local/share/themes` 或应用 CSS，升级会覆盖。
- 看日志：

  ```bash
  tail -50 ~/.local/share/dsh-tauri/logs/desktop.log
  ```

- 宠物置顶和渲染流畅有取舍：`force_xwayland=false` 更接近原生 Wayland，但宠物置顶可能失效；按需选。
- 想登录后安静启动（窗口最小化、只留托盘）见 12.3，别为此改 `force_xwayland`。

### 12.7 系统小习惯

- 改桌面配置前先备份：`cp -a 配置 配置.bak-$(date +%F)`。
- 查“为什么没生效”：

  ```bash
  systemctl --user status org.freedesktop.IBus.session.GNOME.service
  ibus engine
  journalctl --user -b --no-pager | tail -50
  ss -tlnp | grep 3080
  ```

- 改 `/etc/hosts`、证书库、sysctl 这类全局文件，记下原值；S302 退出后记得恢复 hosts。
- 文档和脚本都在本仓库：`README.md` + `scripts/`；下次遇到同类问题先搜标题，再跑脚本。

---

## 免责声明

本文记录的是本机排障过程，命令具有破坏性（改证书库、hosts、系统参数）。复现前请备份，并确认你信任本机的中间人工具。音源/第三方插件涉及版权与安全风险，请自行判断。
