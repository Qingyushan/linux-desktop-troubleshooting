#!/usr/bin/env bash
# 用旧版 NSS（3.98）的 certutil 把 S302 根证书重新导入 Steam 的 NSS 库。
#
# 背景：Steam 的 CEF 使用 ~/.pki/nssdb，且内置的旧版 NSS 3.98
# 无法正确读取系统新版 NSS 3.120 写入的证书条目，表现为
# “Invalid SSL Certificate (error:-202 status:4)”。
#
# 用法：先关闭 Steam，再运行本脚本；脚本会临时下载 Ubuntu noble
# 的 libnss3 3.98 / libnspr4 4.35 包并解压，不修改系统库。
set -euo pipefail

CA=$(ls /usr/local/share/ca-certificates/s302-*-root-ca-*.crt 2>/dev/null | head -1 || true)
if [ -z "$CA" ]; then
  echo "未找到 S302 根证书（/usr/local/share/ca-certificates/s302-*-root-ca-*.crt）" >&2
  echo "请先启动 Steamcommunity_302。" >&2
  exit 1
fi

DB="$HOME/.pki/nssdb"
if [ ! -f "$DB/cert9.db" ]; then
  echo "Steam 的 NSS 库不存在：$DB/cert9.db" >&2
  echo "先启动一次 Steam，让 CEF 创建该目录。" >&2
  exit 1
fi

if pgrep -x steam >/dev/null 2>&1; then
  echo "检测到 Steam 正在运行，先尝试正常关闭……"
  steam -shutdown >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -x steam >/dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -x steam >/dev/null 2>&1; then
    echo "Steam 仍在运行，请手动退出后重试。" >&2
    exit 1
  fi
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

NSS_URL="http://archive.ubuntu.com/ubuntu/pool/main/n/nss/libnss3_3.98-1build1_amd64.deb"
TOOLS_URL="http://archive.ubuntu.com/ubuntu/pool/main/n/nss/libnss3-tools_3.98-1build1_amd64.deb"
NSPR_URL="http://archive.ubuntu.com/ubuntu/pool/main/n/nspr/libnspr4_4.35-1.1build1_amd64.deb"

echo "下载 NSS 3.98 / NSS tools / NSPR 4.35 ……"
curl -fL --retry 3 -o "$TMP/libnss3.deb" "$NSS_URL"
curl -fL --retry 3 -o "$TMP/libnss3-tools.deb" "$TOOLS_URL"
curl -fL --retry 3 -o "$TMP/libnspr4.deb" "$NSPR_URL"

dpkg-deb -x "$TMP/libnss3.deb" "$TMP/nss"
dpkg-deb -x "$TMP/libnss3-tools.deb" "$TMP/tools"
dpkg-deb -x "$TMP/libnspr4.deb" "$TMP/nspr"

CERTUTIL="$TMP/tools/usr/bin/certutil"
NSS_LIB="$TMP/nss/usr/lib/x86_64-linux-gnu"
NSPR_LIB="$TMP/nspr/usr/lib/x86_64-linux-gnu"
export LD_LIBRARY_PATH="$NSS_LIB:$NSPR_LIB${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

"$CERTUTIL" -L -d sql:"$DB" >/dev/null

cp -a "$DB/cert9.db" "$DB/cert9.db.bak-$(date +%Y%m%d-%H%M%S)"

# 删除旧条目，避免 -A 因同名失败
for nick in "Steamcommunity302 Root" "Steamcommunity302"; do
  "$CERTUTIL" -D -d sql:"$DB" -n "$nick" >/dev/null 2>&1 || true
done

"$CERTUTIL" -A -n "Steamcommunity302 Root" -t "C,," -i "$CA" -d sql:"$DB"

echo "== 已用 NSS 3.98 导入 =="
"$CERTUTIL" -L -d sql:"$DB" | grep -i steam || true
echo
echo "现在重新启动 Steam。商店应不再报 -202；语言由注册表决定。"
