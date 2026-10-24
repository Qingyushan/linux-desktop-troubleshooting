#!/usr/bin/env bash
# 给 Ubuntu Dock 增加“单击预览 / 双击按状态收起或弹出所有窗口”。
#
# 背景：Ubuntu Dock（ubuntu-dock@ubuntu.com）没有“双击动作”这个 gsettings；
#       它的 click-action 只有单一行为。本脚本直接改扩展 JS，把
#       FOCUS_MINIMIZE_OR_PREVIEWS 分支换成：
#         多窗口、单击   → 窗口预览列表（延迟 300ms 弹出，给双击判定留时间）
#         多窗口、双击   → 全部收回状态则弹出所有窗口，否则全部收回
#         单窗口、已聚焦 → 收回
#         单窗口、已收回 → 弹出
#
# 用法（必须 root，因为写 /usr/share）：
#   sudo scripts/ubuntu-dock-double-click.sh            # 应用补丁
#   sudo scripts/ubuntu-dock-double-click.sh --dry-run  # 只检查，不写
#   sudo scripts/ubuntu-dock-double-click.sh --remove   # 恢复首次打补丁前的原文件
#
# 生效：Wayland 下无法只重启 Shell，必须注销后重新登录（ReloadExtension 未实现）。
# 升级 gnome-shell-extension-ubuntu-dock 会覆盖本补丁，重跑一次即可。
set -euo pipefail

EXT=/usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com
JS="$EXT/appIcons.js"
ORIG="$EXT/appIcons.js.orig-ubuntu-dock"

MODE="apply"
case "${1:-}" in
    --dry-run) MODE="dry-run" ;;
    --remove|-r) MODE="remove" ;;
    --help|-h)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
    "") ;;
    *) echo "未知参数：$1（可用 --dry-run / --remove）" >&2; exit 2 ;;
esac

if [ ! -f "$JS" ]; then
    echo "找不到 $JS：这台机器没装 Ubuntu Dock？" >&2
    exit 1
fi

if [ "$MODE" = "remove" ]; then
    if [ ! -f "$ORIG" ]; then
        echo "没有找到原始备份 $ORIG；无法自动回滚，请用 dpkg 重装扩展或按文档手动恢复。" >&2
        exit 1
    fi
    cp -a "$ORIG" "$JS"
    echo "已恢复原始 appIcons.js。注销重新登录后生效。"
    exit 0
fi

if [ "$MODE" != "dry-run" ] && [ "$(id -u)" -ne 0 ]; then
    echo "需要 root 权限写 $EXT：" >&2
    echo "  sudo $0 ${1:-}" >&2
    exit 1
fi

TMP_PY="$(mktemp /tmp/ubuntu-dock-patch.XXXXXX.py)"
trap 'rm -f "$TMP_PY"' EXIT

cat >"$TMP_PY" <<'PY'
import pathlib
import re
import shutil
import sys

js = pathlib.Path('/usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com/appIcons.js')
orig = pathlib.Path('/usr/share/gnome-shell/extensions/ubuntu-dock@ubuntu.com/appIcons.js.orig-ubuntu-dock')
mode = sys.argv[1]

text = js.read_text()

block = """            case clickAction.FOCUS_MINIMIZE_OR_PREVIEWS: {
                // [DSH patch v3] 多窗口：单击预览，双击按状态“全部收回/全部弹出”
                try {
                    if (!windows.length) {
                        this.app.activate();
                        break;
                    }
                    const now = GLib.get_monotonic_time();
                    const isDoubleClick = !!this._dshLastClick &&
                        (now - this._dshLastClick) < 350000 &&
                        button === 1 && !modifiers;
                    this._dshLastClick = now;
                    const allMinimized = windows.every(w => w.minimized);

                    if (isDoubleClick && !hasUrgentWindows) {
                        this._dshLastClick = 0;
                        if (this._dshPreviewTimeoutId) {
                            GLib.source_remove(this._dshPreviewTimeoutId);
                            this._dshPreviewTimeoutId = 0;
                        }
                        if (this._previewMenu && this._previewMenu.isOpen)
                            this._previewMenu.close();
                        if (allMinimized)
                            this._activateAllWindows();
                        else
                            this._minimizeWindow(true);
                    } else if (windows.length > 1 || modifiers || button !== 1) {
                        // 多窗口（含已收回）：单击延迟弹预览，给双击判定留时间
                        if (this._dshPreviewTimeoutId)
                            GLib.source_remove(this._dshPreviewTimeoutId);
                        this._dshPreviewTimeoutId = GLib.timeout_add(
                            GLib.PRIORITY_DEFAULT, 300, () => {
                                this._dshPreviewTimeoutId = 0;
                                try {
                                    this._windowPreviews();
                                } catch (e) {
                                    logError(e, 'dsh-preview');
                                }
                                return GLib.SOURCE_REMOVE;
                            });
                    } else if (this.focused && !hasUrgentWindows) {
                        if (!Main.overview.visible)
                            this._minimizeWindow();
                    } else {
                        const [w] = windows;
                        Main.activateWindow(w);
                    }
                } catch (e) {
                    logError(e, 'dsh-dock-click');
                    try {
                        const [w] = windows;
                        if (w)
                            Main.activateWindow(w);
                    } catch (_) {
                        // 忽略：保底失败不再抛
                    }
                }
                break;
            }
"""

pattern = re.compile(r"            case clickAction\.FOCUS_MINIMIZE_OR_PREVIEWS: \{.*?\n            \}\n", re.S)

if mode == 'dry-run':
    m = pattern.search(text)
    if not m:
        print('未找到 FOCUS_MINIMIZE_OR_PREVIEWS 分支（扩展版本可能变了）')
        sys.exit(1)
    print('找到目标分支，可打补丁；当前是否为 v3：', '[DSH patch v3]' in m.group(0))
    sys.exit(0)

if not orig.exists():
    shutil.copy2(js, orig)
    print('首次运行：已保存原始备份 ->', orig)

m = pattern.search(text)
if not m:
    print('未找到 FOCUS_MINIMIZE_OR_PREVIEWS 分支（扩展版本可能变了）', file=sys.stderr)
    sys.exit(1)
js.write_text(text[:m.start()] + block + text[m.end():])
print('已写入 v3 补丁')
PY

python3 "$TMP_PY" "$MODE"

echo
echo "语法检查："
if command -v node >/dev/null 2>&1; then
    node --check "$JS" && echo "  OK"
else
    echo "  没装 node，跳过（注销后若 Dock 消失再用 --remove 回滚）"
fi

echo
echo "下一步：注销 → 重新登录，然后："
echo "  多窗口：单击 = 预览列表；双击 = 全部收回（可见时）/ 全部弹出（已收回时）"
echo "  单窗口：单击 = 收回（已聚焦）/ 弹出（已收回）"
