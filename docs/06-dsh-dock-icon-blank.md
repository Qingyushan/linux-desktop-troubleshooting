# DSH 停靠栏 / 应用菜单图标空白

> 返回索引：[README](../README.md) ｜ 原始位置：§5.1 ｜ 相关脚本：`../scripts/fix-dsh-icon.sh`


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
