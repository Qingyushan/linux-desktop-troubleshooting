#!/usr/bin/env bash
# 启动/聚焦 DSH 桌面客户端。
# 客户端本身就是 3080 的唯一宿主（无头服务已停用），这里不再 stop 任何服务。
set -u
exec /usr/bin/deepseek-harness-desktop "$@"
