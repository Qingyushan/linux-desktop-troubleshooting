#!/usr/bin/env bash
# fix-steam-ntfs-library.sh —— 统一 Steam 库路径与开机挂载点，并清掉重复挂载。
#
# 背景：Steam 库在 NTFS 盘上、且库里有 Proton / Steam Linux Runtime 时，Steam 启动
#       必须能读到这些工具的 toolmanifest.vdf。读不到就把工具登记成 "version 0"，
#       之后启动任何 Windows 游戏都报「兼容性工具失败」：
#           compat_log.txt: Tool 1493710 "Proton Experimental" unsupported version 0.
#       如果同一块盘被 fstab（/mnt/xxx）和 udisks（/run/media/$USER/xxx）各挂一份，
#       ntfs3 对同一卷有两套缓存，既有写坏风险，也会让 Steam 用到"开机时不存在"的路径。
#
# 做法：把 vdf 里的库路径改写到同一块盘的开机挂载点，只保留一个挂载。
#
# 用法：
#   ./scripts/fix-steam-ntfs-library.sh --dry-run   # 只看会改什么（安全）
#   ./scripts/fix-steam-ntfs-library.sh             # 真改（会关掉 Steam）
set -euo pipefail

STEAM_DIR="${STEAM_DIR:-$HOME/.steam/steam}"
LIBRARY_VDF="$STEAM_DIR/steamapps/libraryfolders.vdf"
STEAM_SH="$HOME/.steam/debian-installation/steam.sh"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

say() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

[ -f "$LIBRARY_VDF" ] || die "找不到 $LIBRARY_VDF（Steam 装在别处就设 STEAM_DIR=...）"
[ -x "$STEAM_SH" ] || say "提示：没找到 $STEAM_SH，后面不会自动重启 Steam"

# ---------- 1. 收集所有库路径 ----------
mapfile -t LIBS < <(grep -oP '"path"\s+"\K[^"]+' "$LIBRARY_VDF" | while read -r p; do
    [ -d "$p/steamapps" ] && printf '%s\n' "$p"
done)

[ "${#LIBS[@]}" -gt 0 ] || die "libraryfolders.vdf 里没有可用的库路径"
say "Steam 库：${LIBS[*]}"

# ---------- 2. 算出需要的改写与重复挂载 ----------
declare -a REWRITE_OLD=() REWRITE_NEW=() DUP_MOUNTS=()

for lib in "${LIBS[@]}"; do
    dev="$(findmnt -no SOURCE -T "$lib" 2>/dev/null || true)"
    [ -n "${dev:-}" ] || continue
    fstype="$(findmnt -no FSTYPE -T "$lib" 2>/dev/null || true)"
    cur_mp="$(findmnt -no TARGET -T "$lib" 2>/dev/null || true)"
    mapfile -t mps < <(findmnt -rno TARGET -S "$dev" | awk '!seen[$0]++')

    say ""
    say "库：$lib"
    say "  设备：$dev ($fstype)  挂载点：${mps[*]}"

    if [ "$fstype" = "ntfs" ] || [ "$fstype" = "ntfs3" ] || [ "$fstype" = "fuseblk" ]; then
        say "  提示：NTFS 不是 Proton 官方支持的文件系统；偶发读工具清单失败就该迁到 ext4。"
    fi

    # 当前库位于临时挂载（/run/media/...）时，找同一设备的持久挂载点
    case "$cur_mp" in
        /run/media/*)
            for mp in "${mps[@]}"; do
                case "$mp" in /run/media/*) continue ;; esac
                [ -d "$mp" ] || continue
                rel="${lib#"$cur_mp"}"
                [ -d "$mp$rel/steamapps" ] || continue
                REWRITE_OLD+=("$lib")
                REWRITE_NEW+=("$mp$rel")
                DUP_MOUNTS+=("$cur_mp")
                say "  → 建议改写为：$mp$rel"
                break
            done
            ;;
    esac
done

# 去重（同一挂载点只卸载一次）
if [ "${#DUP_MOUNTS[@]}" -gt 1 ]; then
    mapfile -t DUP_MOUNTS < <(printf '%s\n' "${DUP_MOUNTS[@]}" | awk '!seen[$0]++')
fi

# ---------- 3. dry-run 或无事可做 ----------
if [ "${#REWRITE_OLD[@]}" -eq 0 ] && [ "${#DUP_MOUNTS[@]}" -eq 0 ]; then
    say ""
    say "库路径与挂载点已经一致，什么都不用做。"
    exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
    say ""
    say "[dry-run] 会做："
    for i in "${!REWRITE_OLD[@]}"; do
        say "  · 备份 $LIBRARY_VDF，把 ${REWRITE_OLD[$i]} 改成 ${REWRITE_NEW[$i]}"
    done
    for mp in "${DUP_MOUNTS[@]:-}"; do
        [ -n "$mp" ] && say "  · 卸载重复挂载 $mp"
    done
    say "  · 关闭并重启 Steam"
    exit 0
fi

# ---------- 4. 关闭 Steam ----------
if pgrep -f "debian-installation/steam.sh" >/dev/null 2>&1; then
    say ""
    say "正在关闭 Steam ..."
    "$STEAM_SH" -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do
        pgrep -f "debian-installation/steam.sh" >/dev/null 2>&1 || break
        sleep 1
    done
    pgrep -f "debian-installation/steam.sh" >/dev/null 2>&1 && die "Steam 没退干净，先手动退出再来"
fi

# ---------- 5. 改写库路径 ----------
BAK="$LIBRARY_VDF.bak-$(date +%Y%m%d-%H%M%S)"
cp -a "$LIBRARY_VDF" "$BAK"
say "已备份：$BAK"
python3 - "$LIBRARY_VDF" "${REWRITE_OLD[@]}" -- "${REWRITE_NEW[@]}" <<'PY'
import sys, pathlib
vdf = sys.argv[1]
args = sys.argv[2:]
idx = args.index('--')
olds, news = args[:idx], args[idx+1:]
p = pathlib.Path(vdf)
text = p.read_text(encoding='utf-8')
for o, n in zip(olds, news):
    if o in text:
        text = text.replace(o, n)
        print(f"  已改写：{o} -> {n}")
    else:
        print(f"  跳过（未找到）：{o}")
p.write_text(text, encoding='utf-8')
PY

# ---------- 6. 清理重复挂载 ----------
for mp in "${DUP_MOUNTS[@]:-}"; do
    [ -n "$mp" ] || continue
    say "卸载重复挂载 $mp ..."
    if umount "$mp" 2>/dev/null; then
        say "  已卸载"
    elif sudo -n umount "$mp" 2>/dev/null; then
        say "  已卸载（sudo）"
    elif sudo umount "$mp"; then
        say "  已卸载（sudo）"
    else
        say "  ! 卸载失败，先看看谁在占用：lsof +f -- '$mp' | head"
    fi
done

# ---------- 7. 重启 Steam 并验证 ----------
if [ -x "$STEAM_SH" ]; then
    say ""
    say "重启 Steam ..."
    nohup setsid "$STEAM_SH" >/dev/null 2>&1 &
    sleep 40
    LOG="$HOME/.steam/debian-installation/logs/compat_log.txt"
    if [ -f "$LOG" ] && tail -300 "$LOG" | grep -q "Loaded manifest for tool 1493710"; then
        say "验证：compat_log 里出现「Loaded manifest for tool 1493710」——工具清单读到了。"
    else
        say "验证：还没看到工具清单加载行（Steam 可能仍在启动）。稍后自查："
        say "  grep -E 'Loaded manifest|unsupported version' '$LOG' | tail"
    fi
fi
say ""
say "回滚：cp -a '$BAK' '$LIBRARY_VDF'"
