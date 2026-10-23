#!/bin/bash
# 延迟重启 DSH Tauri：先完全退出，再重新拉起（由本次升级任务临时生成）
set -u
DELAY="${1:-45}"
LOG=/tmp/dsh-relaunch.log
echo "=== $(date -Is) scheduled restart in ${DELAY}s ===" >> "$LOG"
sleep "$DELAY"

OLD=$(pgrep -f '^/usr/bin/deepseek-harness-desktop' | head -1)
if [ -z "${OLD:-}" ]; then
  echo "$(date -Is) no running app found; launching" >> "$LOG"
else
  echo "$(date -Is) sending TERM to $OLD" >> "$LOG"
  kill -TERM "$OLD" 2>/dev/null
  for _ in $(seq 1 30); do
    kill -0 "$OLD" 2>/dev/null || break
    sleep 0.5
  done
  if kill -0 "$OLD" 2>/dev/null; then
    echo "$(date -Is) still alive; KILL" >> "$LOG"
    kill -KILL "$OLD" 2>/dev/null
  fi
fi

sleep 2
setsid nohup /usr/bin/deepseek-harness-desktop >> "$LOG" 2>&1 &
echo "$(date -Is) relaunched pid $!" >> "$LOG"
