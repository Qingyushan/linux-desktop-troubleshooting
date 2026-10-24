#!/usr/bin/env bash
# 给 DSH Web 前端的菜单/浮层加“毛玻璃”外观，并保持可读性。
#
# 背景：菜单材质层（._material_*）的半透明底色是主题在 <body> 运行时注入的
#       （--dsw-menu-surface-fill，深色 #43454a73 / 浅色 #f8f9fa94），
#       只改 CSS 文件里的 :root 变量会被运行时样式盖过；本脚本直接重写
#       材质层的 background-color 与 backdrop-filter，并用 !important 压过。
#
# 用法：
#   scripts/dsh-menu-frost.sh              # 默认 0.82 / 36px（浮层 +0.02 实、+4px 模糊）
#   scripts/dsh-menu-frost.sh 0.65 32      # 更透、模糊更强
#   scripts/dsh-menu-frost.sh --remove     # 移除覆盖，恢复主题原样
#
# 幂等：重复执行只会替换掉上一次追加的块，不会累积。
# 升级 DSH 后重跑一次即可（构建产物 index-*.css 会被重新生成）。
set -euo pipefail

ALPHA="${1:-0.82}"
BLUR="${2:-36}"
MODE="apply"
case "${1:-}" in
    --remove|-r) MODE="remove"; ALPHA="0.82"; BLUR="36" ;;
esac

DRI="$HOME/.local/share/dsh-tauri/dependencies"
shopt -s nullglob
CANDIDATES=("$DRI/dsh"/node_modules/@deepseek-ai/dsh-web-frontend/dist/assets/index-*.css
            "$DRI"/dsh-*/node_modules/@deepseek-ai/dsh-web-frontend/dist/assets/index-*.css)
shopt -u nullglob

[ "${#CANDIDATES[@]}" -gt 0 ] || { echo "找不到 dsh-web-frontend 的构建 CSS，确认 DSH 已安装" >&2; exit 1; }

changed=0
for css in "${CANDIDATES[@]}"; do
    [ -f "$css" ] || continue
    out=$(python3 - "$css" "$ALPHA" "$BLUR" "$MODE" <<'PY'
import re, sys, pathlib

path, alpha, blur, mode = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = pathlib.Path(path)
text = p.read_text()
# 去掉上一次追加的块（到文件末尾）
text = re.sub(r"\n?/\* ===== DSH 定制：.*\Z", "", text, flags=re.S)

if mode == "remove":
    p.write_text(text)
    print("removed")
    raise SystemExit


m = re.search(r"\.(_material_[A-Za-z0-9]+_[A-Za-z0-9]+)", text)
if not m:
    print("no-material-class")
    raise SystemExit(1)
mat = "." + m.group(1)

block = f"""

/* ===== DSH 定制：菜单/浮层毛玻璃（重放：scripts/dsh-menu-frost.sh）=====
   改了数字后重跑脚本。 */
{mat}{{
  background-color: rgba(248,249,250,{alpha}) !important;
  backdrop-filter: blur({blur}px) saturate(150%) !important;
  -webkit-backdrop-filter: blur({blur}px) saturate(150%) !important;
}}
body[data-ds-dark-theme] {mat}{{
  background-color: rgba(67,69,74,{alpha}) !important;
}}
"""
p.write_text(text + block)
print("applied", mat)
PY
)
    case "$out" in
        applied*) echo "  ✔ $css  ($out)"; changed=$((changed+1)) ;;
        removed)  echo "  ✔ $css  已移除覆盖"; changed=$((changed+1)) ;;
        *)        echo "  ✘ $css  跳过：$out" >&2 ;;
    esac
done

[ "$changed" -gt 0 ] || { echo "没有可改的文件" >&2; exit 1; }

if [ "$MODE" = "apply" ]; then
    cat <<EOF

生效方式：
  浏览器：Ctrl+Shift+R 硬刷新
  客户端：Ctrl+R 重载，或退出重开（客户端是 3080 宿主，会断开几秒）

自检（应看到刚追加的块）：
  curl -s http://127.0.0.1:3080/assets/\$(ls $DRI/dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist/assets/index-*.css | xargs -n1 basename) | tail -5
EOF
fi
