#!/usr/bin/env bash
# switch-g1-to-ntfs3g.sh —— 把 NTFS 游戏盘（/dev/sda2，挂 /mnt/G1）从内核 ntfs3 换成
# FUSE 的 ntfs-3g，并顺手修好"文件管理器里看不到这块盘"。
#
# 为什么换驱动：
#   内核 ntfs3 在**并发**创建符号链接时会大量失败（实测 8 进程 × 40 次：失败 192/320；
#   同一目录单线程 0/100 失败）。而 Steam Linux Runtime 的 pressure-vessel 恰好是并发
#   建链接，于是表现为"有时能进游戏、有时 2 秒退出"：
#       pressure-vessel-wrap: E: Unable to create symlink ...: No such file or directory
#   ntfs-3g 把符号链接放在用户态实现，同样的并发测试 0/320 失败，读速基本无损
#   （MiSide 大文件 dd 直读：ntfs3 509 MB/s vs ntfs-3g 505 MB/s）。
#
# 为什么文件管理器里看不到：
#   fstab 挂载的卷默认不进 GNOME「文件」侧栏，需要 x-gvfs-show；x-gvfs-name 只是给它起名。
#
# 关键坑：**不要加 windows_names**！它禁止文件名含冒号，而 Wine 必须创建
#   dosdevices/c: -> ../drive_c，加了就会报 OSError: [Errno 22] Invalid argument。
#
# 用法：sudo bash ./scripts/switch-g1-to-ntfs3g.sh
set -euo pipefail

DEV="${DEV:-/dev/sda2}"
MP="${MP:-/mnt/G1}"
FSTAB=/etc/fstab
UUID="${UUID:-$(grep -oP 'UUID=\K[0-9A-F]+' /etc/fstab | head -1)}"

say() { printf '%s\n' "$*"; }
die() { printf '错误：%s\n' "$*" >&2; exit 1; }
[ "${EUID:-1}" -eq 0 ] || die "请用 sudo 运行：sudo bash $0"

[ -n "${UUID:-}" ] || die "没能从 /etc/fstab 里取到 UUID，请用 UUID=... 指定"

say "== 1. 关闭 Steam（重挂载前必须释放 $MP）=="
if pgrep -u 1000 -f "debian-installation/steam.sh" >/dev/null 2>&1; then
    runuser -u "$(id -nu 1000)" -- /home/"$(id -nu 1000)"/.steam/debian-installation/steam.sh -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
        pgrep -u 1000 -f "debian-installation/steam.sh" >/dev/null 2>&1 || break
        sleep 1
    done
fi

say "== 2. 卸载 $MP =="
umount "$MP" 2>&1 || true
mountpoint -q "$MP" && die "$MP 仍被占用，先手动关掉占用它的程序"

say "== 3. 改写 fstab：fstype=ntfs-3g，补 x-gvfs-show / x-gvfs-name，去掉 windows_names 和 prealloc =="
BAK="$FSTAB.bak-$(date +%Y%m%d-%H%M%S)"
cp -a "$FSTAB" "$BAK"
say "  备份：$BAK"
python3 - "$FSTAB" "$UUID" <<'PYEOF'
import sys, pathlib
fstab, uuid = sys.argv[1], sys.argv[2]
p = pathlib.Path(fstab)
lines = p.read_text().splitlines()
out, done = [], False
for line in lines:
    s = line.strip()
    if s.startswith(f'UUID={uuid}') and not done:
        parts = s.split()
        if len(parts) >= 4:
            parts[2] = 'ntfs-3g'
            opts = [o for o in parts[3].split(',')
                    if o and o not in ('prealloc', 'windows_names')
                    and not o.startswith('x-systemd')]
            names = [o.split('=')[0] for o in opts]
            for extra in ('nofail', 'x-gvfs-show', 'x-gvfs-name=G1',
                          'x-systemd.device-timeout=10'):
                if extra.split('=')[0] not in names:
                    opts.append(extra)
            parts[3] = ','.join(opts)
            line = '   '.join(parts)
            done = True
    out.append(line)
p.write_text('\n'.join(out) + '\n')
print("  fstab 已更新" if done else "  ! 未找到 UUID 行")
PYEOF
grep "^UUID=$UUID" "$FSTAB" | sed 's/^/  /'
systemctl daemon-reload

say "== 4. 按 fstab 重新挂载 =="
mount "$MP"
findmnt -rno TARGET,FSTYPE,OPTIONS -S "$DEV" | sed 's/^/  /'

say "== 5. 验证（以 uid 1000 身份）=="
U="$(id -nu 1000)"
say "  a) 并发符号链接（8×40）："
fails=$(seq 1 320 | xargs -P 8 -I@ runuser -u "$U" -- sh -c 'ln -s /tmp "/mnt/G1/.cc-@" 2>/dev/null && rm -f "/mnt/G1/.cc-@" || echo F' | grep -c F || true)
say "     失败 $fails / 320"
say "  b) 含冒号的符号链接（Wine 的 c: 需要）："
if runuser -u "$U" -- bash -c 'mkdir -p /mnt/G1/.ct && ln -s ../drive_c "/mnt/G1/.ct/c:" && rm -rf /mnt/G1/.ct' 2>/dev/null; then
    say "     OK"
else
    say "     失败 —— 检查 fstab 里是不是还有 windows_names"
fi

say ""
if [ "$fails" -eq 0 ]; then
    say "完成。现在可以直接启动 Steam 跑 Proton 游戏了。"
    say "文件管理器里应该也能看到「G1」（必要时关掉重开「文件」）。"
else
    say "警告：并发符号链接仍有失败（$fails/320），Proton 游戏可能不稳定。"
fi
