#!/usr/bin/env bash
# 把 Steamcommunity_302 的根证书导入 Firefox 的 NSS 库。
# 适用：Firefox 报 SEC_ERROR_UNKNOWN_ISSUER，系统 curl 正常。
# 说明：先备份 cert9.db；导入后必须完全退出 Firefox 再启动。
set -euo pipefail

CA=$(ls /usr/local/share/ca-certificates/s302-*-root-ca-*.crt 2>/dev/null | head -1 || true)
if [ -z "$CA" ]; then
  echo "未找到 S302 根证书（/usr/local/share/ca-certificates/s302-*-root-ca-*.crt）" >&2
  echo "请先启动 Steamcommunity_302，让它安装根证书。" >&2
  exit 1
fi

if [ -d "$HOME/snap/firefox/common/.mozilla/firefox" ]; then
  BASE="$HOME/snap/firefox/common/.mozilla/firefox"
elif [ -d "$HOME/.mozilla/firefox" ]; then
  BASE="$HOME/.mozilla/firefox"
else
  echo "未找到 Firefox 配置目录（snap 或 deb 路径都不存在）" >&2
  exit 1
fi

PROFILE=$(awk -F= '/^Path=/{print $2; exit}' "$BASE/profiles.ini" 2>/dev/null || true)
if [ -z "$PROFILE" ]; then
  PROFILE=$(awk -F= '/^Default=/{print $2; exit}' "$BASE/profiles.ini" 2>/dev/null || true)
fi
if [ -z "$PROFILE" ]; then
  echo "无法从 $BASE/profiles.ini 解析默认 profile" >&2
  exit 1
fi

DB="$BASE/$PROFILE"
if [ ! -f "$DB/cert9.db" ]; then
  echo "cert9.db 不存在：$DB" >&2
  exit 1
fi

cp -a "$DB/cert9.db" "$DB/cert9.db.bak-$(date +%Y%m%d-%H%M%S)"
if certutil -L -d sql:"$DB" 2>/dev/null | grep -qi 'Steamcommunity302'; then
  certutil -D -d sql:"$DB" -n "Steamcommunity302 Root" 2>/dev/null || true
fi
certutil -A -n "Steamcommunity302 Root" -t "C,," -i "$CA" -d sql:"$DB"

echo "== 已导入 =="
certutil -L -d sql:"$DB" | grep -i steam || true
echo
echo "请完全退出 Firefox 再重新启动（Ctrl+Q 或结束所有 firefox 进程）。"
