# 系统小习惯

> 返回索引：[README](../README.md) ｜ 原始位置：§12.7


- 改桌面配置前先备份：`cp -a 配置 配置.bak-$(date +%F)`。
- 查“为什么没生效”：

  ```bash
  systemctl --user status org.freedesktop.IBus.session.GNOME.service
  ibus engine
  journalctl --user -b --no-pager | tail -50
  ss -tlnp | grep 3080
  ```

- 改 `/etc/hosts`、证书库、sysctl 这类全局文件，记下原值；S302 退出后记得恢复 hosts。
- 文档和脚本都在本仓库：`README.md` + `scripts/`；下次遇到同类问题先搜标题，再跑脚本。

---
