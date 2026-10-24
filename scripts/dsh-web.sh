#!/usr/bin/env bash
# 打开 DSH Web 端：3080 没通就先拉起桌面客户端（它负责托管 harness），再开浏览器。
set -u
URL="http://127.0.0.1:3080"
up() { curl -sf --max-time 1 "$URL/" >/dev/null 2>&1; }

if ! up; then
    setsid nohup /home/qys/.local/bin/dsh-client >/dev/null 2>&1 &
    for _ in $(seq 1 90); do
        up && break
        sleep 1
    done
fi

if ! up; then
    notify-send -a DSH "后端没起来：请检查桌面客户端" 2>/dev/null || true
    exit 1
fi

# 优先用 Chrome 打开（可用 CHROME_BIN 覆盖，例如回退到 firefox）
CHROME="${CHROME_BIN:-/usr/bin/google-chrome-stable}"
if [ -x "$CHROME" ]; then
    exec "$CHROME" --new-window "$URL"
fi
if command -v google-chrome >/dev/null 2>&1; then
    exec google-chrome --new-window "$URL"
fi
exec xdg-open "$URL"
