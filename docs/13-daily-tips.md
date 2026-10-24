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

## 启动项：GRUB 菜单等待 3 秒（双系统）

Ubuntu 默认 `GRUB_TIMEOUT_STYLE=hidden` + `GRUB_TIMEOUT=0`，开机**完全不显示菜单**，直接用默认项启动——双系统时想切 Windows 只能靠运气/反复重启。

改成"菜单可见 + 等 3 秒"：

```bash
sudo cp -a /etc/default/grub /etc/default/grub.bak-$(date +%F)

# 两行都要改：
#   GRUB_TIMEOUT_STYLE=hidden → menu   （否则菜单是隐藏的，3 秒只是"看不见的倒数"）
#   GRUB_TIMEOUT=0            → 3
sudo vi /etc/default/grub
sudo update-grub
```

验证生成的 `grub.cfg`（这个文件是 root 600，必须 sudo 读）：

```bash
sudo grep -E "set timeout(_style)?=" /boot/grub/grub.cfg
sudo grep -E "^menuentry|^submenu" /boot/grub/grub.cfg
```

本机改完的样子：

```
      set timeout=3          # 正常启动：等 3 秒
      set timeout=30         # 上一次启动失败（recordfail）→ 等 30 秒，方便进救援
menuentry 'Ubuntu'
submenu 'Advanced options for Ubuntu'
menuentry 'Windows Boot Manager (on /dev/nvme0n1p1)'
```

要点：

- **只改 `GRUB_TIMEOUT` 不改 `GRUB_TIMEOUT_STYLE` 是无效的**：`hidden` 模式下菜单不显示，倒计时结束后仍然进默认项。
- `set timeout=30` 那条是 `recordfail` 分支（上次没启动成功时延长等待），属于正常保护，不用改。
- Windows 条目来自 os-prober；本机默认就启用了（`update-grub` 日志里有 `Warning: os-prober will be executed ...`）。如果日志里没有这行、菜单里也没有 Windows，就要在 `/etc/default/grub` 里加 `GRUB_DISABLE_OS_PROBER=false` 并 `sudo apt install os-prober`。
- 回滚：`sudo cp -a /etc/default/grub.bak-<时间> /etc/default/grub && sudo update-grub`。
- 这是纯配置改动，**不需要** `grub-install`，下次开机生效。
