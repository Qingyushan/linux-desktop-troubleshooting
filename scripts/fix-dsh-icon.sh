#!/usr/bin/env bash
# Restore the DSH Tauri icon in GNOME Shell without touching /usr/share.
#
# What it does:
#   1. copies the packaged icon to a NEW name under the user icon theme;
#   2. writes a user-level desktop override pointing at the new file;
#   3. refreshes the desktop database and the user icon cache.
#
# It does not kill or restart the app; see the message at the end.

set -euo pipefail

APP_NAME="DSH Tauri"
DESKTOP_NAME="${APP_NAME}.desktop"
SOURCE_ICON="deepseek-harness-desktop"
NEW_ICON="deepseek-harness-desktop-visible"
SIZES=(32x32 128x128 256x256@2 512x512)

USER_ICON_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
USER_DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
SYSTEM_DESKTOP="/usr/share/applications/${DESKTOP_NAME}"
USER_DESKTOP="${USER_DESKTOP_DIR}/${DESKTOP_NAME}"

if [[ ! -f "$SYSTEM_DESKTOP" ]]; then
  echo "error: $SYSTEM_DESKTOP not found; is dsh-tauri installed?" >&2
  exit 1
fi

if [[ ! -f "/usr/share/icons/hicolor/512x512/apps/${SOURCE_ICON}.png" ]]; then
  echo "error: packaged icon /usr/share/icons/hicolor/512x512/apps/${SOURCE_ICON}.png not found" >&2
  exit 1
fi

echo "==> installing user icons as ${NEW_ICON}"
for size in "${SIZES[@]}"; do
  src="/usr/share/icons/hicolor/${size}/apps/${SOURCE_ICON}.png"
  dst="${USER_ICON_ROOT}/${size}/apps/${NEW_ICON}.png"
  if [[ ! -f "$src" ]]; then
    echo "warning: missing $src, skipping" >&2
    continue
  fi
  install -Dm644 "$src" "$dst"
  echo "    $dst"
done

echo "==> writing user desktop override"
mkdir -p "$USER_DESKTOP_DIR"
if [[ -f "$USER_DESKTOP" ]]; then
  backup="${USER_DESKTOP}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "$USER_DESKTOP" "$backup"
  echo "    backup: $backup"
fi
cp -a "$SYSTEM_DESKTOP" "$USER_DESKTOP"
sed -i "s|^Icon=.*|Icon=${USER_ICON_ROOT}/512x512/apps/${NEW_ICON}.png|" "$USER_DESKTOP"
# Keep the shell association explicit even if the package changes it later.
if grep -q '^StartupWMClass=' "$USER_DESKTOP"; then
  sed -i 's|^StartupWMClass=.*|StartupWMClass=deepseek-harness-desktop|' "$USER_DESKTOP"
else
  printf 'StartupWMClass=deepseek-harness-desktop\n' >> "$USER_DESKTOP"
fi

echo "==> refreshing caches"
update-desktop-database "$USER_DESKTOP_DIR" 2>/dev/null || true
gtk-update-icon-cache -f -t "$USER_ICON_ROOT" 2>/dev/null || true

echo
echo "done. verify the entry:"
echo "  gjs -c 'const Gio=imports.gi.Gio; print(Gio.DesktopAppInfo.new(\"${DESKTOP_NAME}\").get_icon().to_string())'"
echo
echo "Now fully quit DSH and start it again:"
echo "  pkill -f '^/usr/bin/deepseek-harness-desktop$' || true"
echo
echo "If the dock icon is still blank, the X11 window has no _NET_WM_ICON;"
echo "set one for the current window (temporary) or check StartupWMClass with:"
echo "  xprop -id <window-id> _NET_WM_ICON WM_CLASS"
