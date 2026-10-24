#!/usr/bin/env bash
# proton-tools-on-ext4.sh —— 只把 Proton 工具和 Wine 前缀放到内部 ext4 盘，
# 游戏本体（MiSide 4.1G）继续留在 NTFS 库。目的：避开 NTFS 上建符号链接不稳定的坑，
# 同时不搬大文件、不多占内部盘。
#
# 原理：
#   - Steam Linux Runtime 的 pressure-vessel 容器会在 <runtime>/var/tmp-*/usr 里建符号链接，
#     所以 runtime 必须在 ext4 上；Proton 同理（同目录下的 dist.lock/prefix 操作）。
#   - Wine 前缀（dosdevices/*）也全是符号链接，前缀也必须在 ext4 上。
#     → 用启动项 STEAM_COMPAT_DATA_PATH 把前缀指到内部盘。
#   - 游戏本体只被读取，不需要建链接，留在 NTFS 没问题。
#
# 用法：
#   ./scripts/proton-tools-on-ext4.sh            # 迁移（只搬工具 + 前缀指向内部盘）
#   ./scripts/proton-tools-on-ext4.sh --revert   # 回滚（工具搬回 NTFS、删掉启动项）
set -euo pipefail

APPID=2527500
REVERT=0
[ "${1:-}" = "--revert" ] && REVERT=1
SRC_LIB="/mnt/G1/SteamLibrary"
DST_LIB="$HOME/.steam/debian-installation"
STEAM_SH="$DST_LIB/steam.sh"
TOOLS=("Proton - Experimental" "SteamLinuxRuntime_4")
TOOL_ACFS=(1493710 4183110)
EXT_PREFIX="$DST_LIB/steamapps/compatdata/$APPID"
LOCALCONFIG="$HOME/.steam/steam/userdata/1781787943/config/localconfig.vdf"

say() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

[ -d "$SRC_LIB/steamapps/common/MiSide" ] || die "MiSide 不在 $SRC_LIB"

# 1. 关 Steam
if pgrep -f "debian-installation/steam.sh" >/dev/null 2>&1; then
    say "关闭 Steam ..."
    "$STEAM_SH" -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do
        pgrep -f "debian-installation/steam.sh" >/dev/null 2>&1 || break
        sleep 1
    done
    pgrep -f "debian-installation/steam.sh" >/dev/null 2>&1 && die "Steam 没退干净"
fi

# ---------- 回滚分支：工具搬回 NTFS，删掉启动项 ----------
if [ "$REVERT" -eq 1 ]; then
    mkdir -p "$SRC_LIB/steamapps/common"
    for d in "${TOOLS[@]}"; do
        src="$DST_LIB/steamapps/common/$d"
        dst="$SRC_LIB/steamapps/common/$d"
        [ -d "$src" ] || { say "内部盘没有：$d"; continue; }
        if [ -d "$dst" ]; then
            say "NTFS 上已存在，跳过：$d"
        else
            say "搬回：$d ..."
            cp -a "$src" "$dst"
            src_kb=$(du -sk "$src" | cut -f1); dst_kb=$(du -sk "$dst" | cut -f1)
            say "  ${src_kb} KB → ${dst_kb} KB"
            [ "$dst_kb" -ge $((src_kb * 95 / 100)) ] || die "回滚不完整：$d"
        fi
        rm -rf "$src"
    done
    for id in "${TOOL_ACFS[@]}"; do
        f="$DST_LIB/steamapps/appmanifest_$id.acf"
        if [ -f "$f" ]; then
            cp -a "$f" "$SRC_LIB/steamapps/"
            rm -f "$f"
            say "已搬回 appmanifest_$id.acf"
        fi
    done
    if [ -f "$LOCALCONFIG" ]; then
        BAK="$LOCALCONFIG.bak-$(date +%Y%m%d-%H%M%S)"
        cp -a "$LOCALCONFIG" "$BAK"
        python3 - "$LOCALCONFIG" <<'PYEOF'
import re, sys, pathlib
p = pathlib.Path(sys.argv[1])
t = p.read_text(encoding='utf-8', errors='replace')
new = re.sub(r'\n[ \t]*"LaunchOptions"\t\t"STEAM_COMPAT_DATA_PATH=[^"]*"', '', t)
p.write_text(new, encoding='utf-8')
print("  已删除 STEAM_COMPAT_DATA_PATH 启动项" if new != t else "  启动项本来就是空的")
PYEOF
        say "  备份：$BAK"
    fi
    say ""
    say "回滚完成。启动 Steam："
    say "  nohup setsid \"$STEAM_SH\" >/dev/null 2>&1 &"
    exit 0
fi

# 2. 搬工具（只搬工具，游戏不动）
mkdir -p "$DST_LIB/steamapps/common"
for d in "${TOOLS[@]}"; do
    src="$SRC_LIB/steamapps/common/$d"
    dst="$DST_LIB/steamapps/common/$d"
    [ -d "$src" ] || { say "源不存在，跳过：$d"; continue; }
    if [ -d "$dst" ]; then
        say "目标已存在，跳过：$d"
    else
        say "复制工具：$d ..."
        cp -a "$src" "$dst"
        src_kb=$(du -sk "$src" | cut -f1); dst_kb=$(du -sk "$dst" | cut -f1)
        say "  ${src_kb} KB → ${dst_kb} KB"
        [ "$dst_kb" -ge $((src_kb * 95 / 100)) ] || die "复制不完整：$d"
    fi
    say "删除 NTFS 上的副本：$d"
    rm -rf "$src"
done
for id in "${TOOL_ACFS[@]}"; do
    f="$SRC_LIB/steamapps/appmanifest_$id.acf"
    if [ -f "$f" ]; then
        cp -a "$f" "$DST_LIB/steamapps/"
        rm -f "$f"
        say "已搬 appmanifest_$id.acf"
    fi
done

# 3. 内部盘上准备前缀目录
mkdir -p "$EXT_PREFIX"
say "前缀目录：$EXT_PREFIX"

# 4. 给这个游戏加启动项，把前缀指到内部盘
say ""
say "写入启动项（localconfig.vdf）..."
BAK="$LOCALCONFIG.bak-$(date +%Y%m%d-%H%M%S)"
cp -a "$LOCALCONFIG" "$BAK"
python3 - "$LOCALCONFIG" "$APPID" "$EXT_PREFIX" <<'PY'
import sys, pathlib
vdf, appid, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(vdf)
text = p.read_text(encoding='utf-8', errors='replace')
launch = f'STEAM_COMPAT_DATA_PATH={prefix} %command%'

# 已经有这个 appid 的条目就改 LaunchOptions，否则插到 apps 块开头
key = f'"{appid}"'
idx_apps = text.find('"apps"')
if idx_apps < 0:
    sys.exit("没找到 apps 段")
brace = text.find('{', idx_apps)
end = text.find('\n', brace)
indent = '\t' * 5

if key in text[idx_apps:]:
    i = text.find(key, idx_apps)
    j = text.find('{', i)
    if '"LaunchOptions"' in text[j:j+400]:
        k = text.find('"LaunchOptions"', j)
        k_end = text.find('\n', k)
        text = text[:k] + f'"LaunchOptions"\t\t"{launch}"' + text[k_end:]
        print("  已更新已有条目的 LaunchOptions")
    else:
        text = text[:j+1] + f'\n{indent}\t"LaunchOptions"\t\t"{launch}"' + text[j+1:]
        print("  已在已有条目里插入 LaunchOptions")
else:
    block = (f'\n{indent}{key}\n{indent}{{\n'
             f'{indent}\t"LaunchOptions"\t\t"{launch}"\n{indent}}}')
    text = text[:end] + block + text[end:]
    print("  已新增条目与 LaunchOptions")
p.write_text(text, encoding='utf-8')
PY
say "  备份：$BAK"

# 5. 启 Steam
say ""
say "启动 Steam ..."
nohup setsid "$STEAM_SH" >/dev/null 2>&1 &
sleep 40
say ""
say "== 状态 =="
say "内部盘工具：$(ls "$DST_LIB/steamapps/common" | tr '\n' ' ')"
say "G1 库还在  ：$(ls "$SRC_LIB/steamapps/common" | grep -c . ) 个目录（MiSide 应保留）"
grep -h "Loaded .* apps from install folder" "$DST_LIB/logs/content_log.txt" 2>/dev/null | tail -2
say ""
say "下一步：在 Steam 里启动 MiSide，然后看："
say "  tail -5 $DST_LIB/logs/compat_log.txt"
say "  ls -d $EXT_PREFIX/pfx"
