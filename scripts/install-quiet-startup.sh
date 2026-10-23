#!/usr/bin/env bash
# install-quiet-startup.sh —— 让 QQ / 微信 / DSH 桌面端「安静」开机自启：
#   应用照常自启，但登录后 150 秒内创建的窗口会被立刻最小化，只留托盘图标。
#
# 原理：Wayland 下外部进程无法最小化别人的窗口（xdotool 只对 XWayland 有效，
#       DSH 桌面端和微信 4.x 都是原生 Wayland 窗口），所以用一个小 GNOME Shell
#       扩展在 shell 内部调用 MetaWindow.minimize()。
#
# 依赖：GNOME Shell 45+（本机 50.1）。不需要 xdotool。
# 幂等：可重复执行；会覆盖本仓库管理的 3 个 autostart 入口。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$REPO_DIR/gnome-extension/quiet-startup@local"
UUID="quiet-startup@local"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$UUID"
CFG_DIR="$HOME/.config/quiet-startup"
AUTOSTART_DIR="$HOME/.config/autostart"

say() { printf '%s\n' "$*"; }

if [ ! -f "$SRC_DIR/extension.js" ] || [ ! -f "$SRC_DIR/metadata.json" ]; then
    echo "找不到扩展源码：$SRC_DIR" >&2
    exit 1
fi

if ! command -v gnome-shell >/dev/null 2>&1; then
    echo "没有 gnome-shell，这个脚本只适用于 GNOME 桌面。" >&2
    exit 1
fi

# 1) 安装扩展
mkdir -p "$EXT_DIR"
cp -f "$SRC_DIR/metadata.json" "$SRC_DIR/extension.js" "$EXT_DIR/"
chmod 644 "$EXT_DIR"/*.js "$EXT_DIR"/*.json
say "已安装扩展：$EXT_DIR"

# 2) 配置（只补缺，不覆盖手工调过的）
mkdir -p "$CFG_DIR"
if [ ! -f "$CFG_DIR/config.json" ]; then
    cat > "$CFG_DIR/config.json" <<'JSON'
{
  "loginWindowSeconds": 150,
  "maxRetries": 3,
  "apps": [
    "deepseek-harness-desktop",
    "deepseek-harness",
    "dsh-tauri",
    "qq",
    "wechat",
    "weixin",
    "xwechat"
  ]
}
JSON
    say "已写入配置：$CFG_DIR/config.json"
else
    say "保留已有配置：$CFG_DIR/config.json"
fi

# 3) autostart 入口（延迟错开，避免登录瞬间抢资源）
mkdir -p "$AUTOSTART_DIR"

cat > "$AUTOSTART_DIR/wechat.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=WeChat
Name[zh_CN]=微信
Comment=Start WeChat quietly at login (window minimized to tray)
Comment[zh_CN]=登录后安静启动微信：主窗口直接最小化，只留托盘图标
Exec=/usr/bin/wechat
Icon=/usr/share/icons/hicolor/512x512/apps/wechat.png
Terminal=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=8
DESKTOP

cat > "$AUTOSTART_DIR/qq.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=QQ
Comment=Start QQ quietly at login (window minimized to tray)
Comment[zh_CN]=登录后安静启动 QQ：主窗口直接最小化，只留托盘图标
Exec=/opt/QQ/qq
Icon=/usr/share/icons/hicolor/512x512/apps/qq.png
Terminal=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=12
DESKTOP

cat > "$AUTOSTART_DIR/deepseek-harness-desktop.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=DeepSeek Harness Desktop
Comment=DeepSeek Harness 桌面客户端（登录后安静启动，窗口最小化到托盘）
Exec=/usr/bin/deepseek-harness-desktop
Icon=deepseek-harness-desktop
Terminal=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
DESKTOP

# 旧 AppImage 时代留下的重复入口会让 DSH 被拉两次，挪出 autostart 目录
if [ -f "$AUTOSTART_DIR/Deepseek Harness Desktop.desktop" ]; then
    mkdir -p "$HOME/.config/autostart-disabled"
    mv -f "$AUTOSTART_DIR/Deepseek Harness Desktop.desktop" "$HOME/.config/autostart-disabled/"
    say "已把重复的旧 DSH 自启入口移到 ~/.config/autostart-disabled/"
fi

# 4) 在 dconf 里启用扩展（保留已有的其它扩展）
current="$(gsettings get org.gnome.shell enabled-extensions)"
if printf '%s' "$current" | grep -q "'$UUID'"; then
    say "扩展已在启用列表里：$current"
else
    updated="$(python3 - "$current" "$UUID" <<'PY'
import ast, sys
try:
    items = list(ast.literal_eval(sys.argv[1]))
except Exception:
    items = []
uuid = sys.argv[2]
if uuid not in items:
    items.append(uuid)
print("[" + ", ".join("'%s'" % i for i in items) + "]")
PY
)"
    gsettings set org.gnome.shell enabled-extensions "$updated"
    say "已启用扩展：$updated"
fi

say ""
say "完成。扩展要等 GNOME Shell 重新加载后才会生效 —— 注销重登（或重启）一次。"
say ""
say "重登后这样验证："
say "  gnome-extensions info $UUID          # State 应为 ENABLED"
say "  cat /tmp/quiet-startup.log           # 应看到 minimize(created#1): app=... 行"
say ""
say "如果某个应用的窗口还是弹出来了：看日志里 created: 后面的名字，"
say "把它加进 $CFG_DIR/config.json 的 apps 数组，然后："
say "  gnome-extensions disable $UUID && gnome-extensions enable $UUID"
