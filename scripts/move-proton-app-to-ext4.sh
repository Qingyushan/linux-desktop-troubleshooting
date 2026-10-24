#!/usr/bin/env bash
# move-proton-app-to-ext4.sh —— 把某个 Proton 游戏连同它依赖的兼容性工具，从一个
# 库（默认 NTFS 的 /mnt/G1/SteamLibrary）搬到内部 ext4 库（~/.steam/debian-installation）。
#
# 为什么必须搬：ntfs3 在这台机器上不允许普通用户创建符号链接（实测 ENOENT，试过
#   uid/gid、umask=0000、dmask/fmask=0000 三套挂载选项都不行），而 Steam Linux Runtime
#   的 pressure-vessel 容器和 Wine 前缀都必须建符号链接，所以 Proton 游戏只能放在
#   Linux 原生文件系统上。
#
# 用法：
#   ./scripts/move-proton-app-to-ext4.sh 2527500            # MiSide
#   ./scripts/move-proton-app-to-ext4.sh 2527500 --dry-run  # 只打印会做什么
#   SRC_LIB=... DST_LIB=... ./scripts/move-proton-app-to-ext4.sh <appid>
set -euo pipefail

SRC_LIB="${SRC_LIB:-/mnt/G1/SteamLibrary}"
DST_LIB="${DST_LIB:-$HOME/.steam/debian-installation}"
STEAM_SH="${STEAM_SH:-$HOME/.steam/debian-installation/steam.sh}"
APPID="${1:-}"
[ -n "$APPID" ] || { echo "用法：$0 <appid> [--dry-run]" >&2; exit 2; }
DRY_RUN=0
[ "${2:-}" = "--dry-run" ] && DRY_RUN=1

say() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

ACF="$SRC_LIB/steamapps/appmanifest_$APPID.acf"
[ -f "$ACF" ] || die "找不到 $ACF（这个 appid 不在 $SRC_LIB 里？）"
GAME_DIR="$(grep -oP '"installdir"\s+"\K[^"]+' "$ACF")"
GAME_NAME="$(grep -oP '"name"\s+"\K[^"]+' "$ACF")"
[ -n "$GAME_DIR" ] || die "读不出 installdir"

# 需要一起搬的：游戏本体 + 库里所有 Proton / Steam Linux Runtime 工具
mapfile -t TOOLS < <(cd "$SRC_LIB/steamapps/common" 2>/dev/null && \
    ls -d Proton* SteamLinuxRuntime* 2>/dev/null || true)
DIRS=("$GAME_DIR" "${TOOLS[@]}")

say "游戏：$GAME_NAME ($APPID)  目录：$GAME_DIR"
say "源库：$SRC_LIB"
say "目标：$DST_LIB"
say "要搬：${DIRS[*]}"

# 对应 appmanifest：游戏本体 + 每个工具（工具用 installdir 反查）
declare -a ACFS=("$APPID")
for t in "${TOOLS[@]}"; do
    id="$(grep -l "\"installdir\"[[:space:]]*\"$t\"" "$SRC_LIB"/steamapps/appmanifest_*.acf 2>/dev/null \
          | head -1 | grep -oP 'appmanifest_\K[0-9]+' || true)"
    if [ -n "${id:-}" ]; then
        ACFS+=("$id")
    fi
done
say "对应 appmanifest：${ACFS[*]}"

need_kb=0
for d in "${DIRS[@]}"; do
    [ -d "$SRC_LIB/steamapps/common/$d" ] || continue
    need_kb=$((need_kb + $(du -sk "$SRC_LIB/steamapps/common/$d" | cut -f1)))
done
free_kb=$(df -k --output=avail "$DST_LIB" | tail -1 | tr -d ' ')
say "需要 $((need_kb/1024/1024)) GB，内部盘剩余 $((free_kb/1024/1024)) GB"

if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] 会：关闭 Steam → cp -a 上述目录与 acf → 删掉 NTFS 上的旧副本 → 删旧前缀 → 重启 Steam"
    exit 0
fi

[ "$free_kb" -gt $((need_kb + 1048576)) ] || die "内部盘空间不足（要留 1 GB 余量）"

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

# 2. 复制 + 校验
mkdir -p "$DST_LIB/steamapps/common"
for d in "${DIRS[@]}"; do
    src="$SRC_LIB/steamapps/common/$d"
    [ -d "$src" ] || continue
    if [ -d "$DST_LIB/steamapps/common/$d" ]; then
        say "目标已存在，跳过：$d"
        continue
    fi
    say "复制：$d ..."
    cp -a "$src" "$DST_LIB/steamapps/common/"
    src_kb=$(du -sk "$src" | cut -f1)
    dst_kb=$(du -sk "$DST_LIB/steamapps/common/$d" | cut -f1)
    say "  ${src_kb} KB → ${dst_kb} KB"
    [ "$dst_kb" -ge $((src_kb * 95 / 100)) ] || die "复制不完整：$d"
done

for id in "${ACFS[@]}"; do
    f="$SRC_LIB/steamapps/appmanifest_$id.acf"
    if [ -f "$f" ]; then
        cp -a "$f" "$DST_LIB/steamapps/"
        say "已复制 appmanifest_$id.acf"
    fi
done

# 3. 删掉 NTFS 上的旧副本（同一 appid 不能同时待在两个库）
for d in "${DIRS[@]}"; do
    if [ -d "$DST_LIB/steamapps/common/$d" ] && [ -d "$SRC_LIB/steamapps/common/$d" ]; then
        say "删除旧副本：$d"
        rm -rf "$SRC_LIB/steamapps/common/$d"
    fi
done
for id in "${ACFS[@]}"; do
    if [ -f "$DST_LIB/steamapps/appmanifest_$id.acf" ]; then
        rm -f "$SRC_LIB/steamapps/appmanifest_$id.acf"
    fi
done

# 4. 旧前缀在 NTFS 上、s: 链接已失效 → 删掉重建
OLD_PREFIX="$SRC_LIB/steamapps/compatdata/$APPID"
if [ -d "$OLD_PREFIX" ]; then
    say "删除 NTFS 上的旧 Wine 前缀（Proton 会在新库重建；存档如需保留请先手动备份）"
    rm -rf "$OLD_PREFIX"
fi

# 5. 启 Steam 并验证
say "启动 Steam ..."
nohup setsid "$STEAM_SH" >/dev/null 2>&1 &
sleep 45
LOG_DIR="$DST_LIB/logs"
say ""
say "== 验证 =="
grep -h "Loaded .* apps from install folder" "$LOG_DIR/content_log.txt" 2>/dev/null | tail -2 || true
say "工具前缀：" ; grep -h "Command prefix for tool .*Proton" "$LOG_DIR/compat_log.txt" 2>/dev/null | tail -1 | cut -c1-160
say ""
say "下一步：在 Steam 里启动「$GAME_NAME」，然后看："
say "  tail -20 $LOG_DIR/compat_log.txt"
