#!/bin/bash
# 安装 DSH 的启动器 / 桌面入口 / systemd 单元（幂等，可重复执行）。
#
# 装出来的东西：
#   ~/.local/bin/dsh-web              打开 Web 端（3080 不通就先拉起桌面客户端）
#   ~/.local/bin/dsh-client           启动桌面客户端（3080 的唯一宿主）
#   ~/.local/bin/dsh-set-appearance   改客户端外观（模糊 / 透明度）
#   ~/.local/share/applications/dsh-web.desktop       「DeepSeek Harness（网页版）」
#   ~/.local/share/applications/DSH Tauri.desktop     覆盖 deb 自带条目，Exec 走 dsh-client
#   ~/.config/systemd/user/dsh-harness.service        无头服务（默认不启用，见文末）
#   ~/.config/systemd/user/dsh-appearance.service     登录时强制 blur=off
#
# 用法：./scripts/install-dsh-launchers.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
UNIT="$HOME/.config/systemd/user"

mkdir -p "$BIN" "$APPS" "$UNIT"

install -m 755 "$HERE/dsh-web.sh"          "$BIN/dsh-web"
install -m 755 "$HERE/dsh-client.sh"       "$BIN/dsh-client"
install -m 755 "$HERE/dsh-set-appearance.py" "$BIN/dsh-set-appearance"

cp -f "$ROOT/systemd/dsh-harness.service" "$ROOT/systemd/dsh-appearance.service" "$UNIT/"

# 「网页版」入口
cat > "$APPS/dsh-web.desktop" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=DeepSeek Harness（网页版）
Name[zh_CN]=DeepSeek Harness（网页版）
Comment=Open the DSH web UI in Firefox; starts the desktop client if the backend is down
Comment[zh_CN]=在 Firefox 中打开 DSH Web 端；后端未起会自动拉起桌面客户端
Exec=$BIN/dsh-web
Icon=deepseek-harness-desktop-visible
Terminal=false
Categories=Development;Network;
StartupNotify=true
Keywords=DSH;DeepSeek;Harness;web;
EOF

# 客户端入口：同名覆盖 deb 自带的 DSH Tauri.desktop，Exec 改成包装器
if [ -f "/usr/share/applications/DSH Tauri.desktop" ]; then
    cp -f "/usr/share/applications/DSH Tauri.desktop" "$APPS/DSH Tauri.desktop"
    sed -i "s|^Exec=.*|Exec=$BIN/dsh-client|" "$APPS/DSH Tauri.desktop"
fi

update-desktop-database "$APPS" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable dsh-appearance.service >/dev/null 2>&1 || true

echo "完成："
echo "  $BIN/dsh-web、dsh-client、dsh-set-appearance"
echo "  $APPS/dsh-web.desktop、DSH Tauri.desktop"
echo "  $UNIT/dsh-harness.service（未启用）、dsh-appearance.service（已启用）"
echo
echo "当前策略：桌面客户端是 3080 的唯一宿主，所以 dsh-harness.service 保持 disabled；"
echo "  要用无头服务：systemctl --user disable --now deepseek-harness-desktop 之后"
echo "                systemctl --user enable --now dsh-harness.service"
