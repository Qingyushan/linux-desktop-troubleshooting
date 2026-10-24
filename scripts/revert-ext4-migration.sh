#!/usr/bin/env bash
# revert-ext4-migration.sh —— 撤销 move-proton-app-to-ext4.sh 的迁移：
# 把 MiSide + Proton Experimental + Steam Linux Runtime 4.0 从内部 ext4 库搬回
# /mnt/G1/SteamLibrary，并清掉内部盘上的副本与前缀。
set -euo pipefail

SRC_LIB="$HOME/.steam/debian-installation"      # 内部 ext4 库（现在的来源）
DST_LIB="/mnt/G1/SteamLibrary"                  # NTFS 库（目标）
STEAM_SH="$SRC_LIB/steam.sh"

DIRS=("MiSide" "Proton - Experimental" "SteamLinuxRuntime_4")
ACFS=(2527500 1493710 4183110)

say() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }

[ -d "$SRC_LIB/steamapps/common/MiSide" ] || die "内部库里没有 MiSide，不用回滚"
[ -d "$DST_LIB/steamapps" ] || die "目标库不存在：$DST_LIB"

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

# 2. 搬回去
mkdir -p "$DST_LIB/steamapps/common"
for d in "${DIRS[@]}"; do
    src="$SRC_LIB/steamapps/common/$d"
    dst="$DST_LIB/steamapps/common/$d"
    [ -d "$src" ] || continue
    if [ -d "$dst" ]; then
        say "目标已存在，跳过：$d"
        continue
    fi
    say "回滚：$d ..."
    cp -a "$src" "$dst"
    src_kb=$(du -sk "$src" | cut -f1)
    dst_kb=$(du -sk "$dst" | cut -f1)
    say "  ${src_kb} KB → ${dst_kb} KB"
    [ "$dst_kb" -ge $((src_kb * 95 / 100)) ] || die "回滚不完整：$d"
done

for id in "${ACFS[@]}"; do
    f="$SRC_LIB/steamapps/appmanifest_$id.acf"
    if [ -f "$f" ]; then
        cp -a "$f" "$DST_LIB/steamapps/"
        say "已回滚 appmanifest_$id.acf"
    fi
done

# 3. 删掉内部盘的副本（腾出空间）
for d in "${DIRS[@]}"; do
    if [ -d "$DST_LIB/steamapps/common/$d" ] && [ -d "$SRC_LIB/steamapps/common/$d" ]; then
        say "删除内部盘副本：$d"
        rm -rf "$SRC_LIB/steamapps/common/$d"
    fi
done
for id in "${ACFS[@]}"; do
    if [ -f "$DST_LIB/steamapps/appmanifest_$id.acf" ]; then
        rm -f "$SRC_LIB/steamapps/appmanifest_$id.acf"
    fi
done

# 4. 内部盘上那个为迁移新建的前缀也删掉（存档只有成就标记）
if [ -d "$SRC_LIB/steamapps/compatdata/2527500" ]; then
    say "删除内部盘上的 Wine 前缀（NTFS 库会重建）"
    rm -rf "$SRC_LIB/steamapps/compatdata/2527500"
fi

say ""
say "== 回滚完成 =="
say "G1 库 common ：$(ls "$DST_LIB/steamapps/common" | tr '\n' ' ')"
say "G1 库 acf    ：$(ls "$DST_LIB/steamapps"/*.acf | xargs -n1 basename | tr '\n' ' ')"
say "内部盘剩余   ：$(df -h "$SRC_LIB" | tail -1 | awk '{print $4}')"
