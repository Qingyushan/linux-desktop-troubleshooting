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

**先纠正一个容易看错的地方**：只看 `/etc/default/grub` 会得出错误结论。

本机原来的 `/etc/default/grub` 写的是：

```
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
```

看起来是"不显示菜单、立即启动"，但**实际开机是显示菜单、等 10 秒**。原因在生成的 `grub.cfg` 末尾——这段由 `/etc/grub.d/30_os-prober` 追加，**只有检测到第二个系统时才会出现**：

```
set timeout_style=menu
if [ "${timeout}" = 0 ]; then
  set timeout=10
fi
```

也就是：**多系统机器上，`hidden + 0` 会被兜底成 `menu + 10 秒`**。所以判断真实等待时间必须读生成后的 `/boot/grub/grub.cfg`（root 600，要 sudo），不能只看 `/etc/default/grub`。

改成 3 秒：

```bash
sudo cp -a /etc/default/grub /etc/default/grub.bak-$(date +%F)

# 建议两行都改：
#   GRUB_TIMEOUT_STYLE=hidden → menu   （显式声明，不依赖 os-prober 兜底）
#   GRUB_TIMEOUT=0            → 3
sudo vi /etc/default/grub
sudo update-grub
```

验证（要 sudo）：

```bash
sudo grep -n -B6 -A2 "set timeout" /boot/grub/grub.cfg
```

本机改完后的关键三段：

```
if [ "${recordfail}" = 1 ] ; then
  set timeout=30            # 上次启动失败才用，属正常保护
else
  ...
    set timeout_style=menu  # 正常分支：菜单可见
    set timeout=3           #          等 3 秒
  ...
fi
```

```
set timeout_style=menu      # 30_os-prober 的兜底
if [ "${timeout}" = 0 ]; then
  set timeout=10            # timeout 已经是 3，这里不触发
fi
```

要点：

- **只改 `GRUB_TIMEOUT=3` 在这台机器上其实也能生效**：os-prober 的兜底会把 `timeout_style` 强制设成 `menu`，而 `timeout≠0` 又让 10 秒那段不触发。我最初说"只改 timeout 无效"是错的。
- 但仍然建议**显式写 `GRUB_TIMEOUT_STYLE=menu`**：兜底块只在检测到第二个系统时存在。将来如果删掉 Windows、或禁用 os-prober，兜底块会消失，那时 `hidden + 0` 就真的变成"不显示菜单"了。
- `set timeout=30` 是 recordfail（上次没启动成功）的延长等待，不要动。
- Windows 条目来自 os-prober；若菜单里没有 Windows，检查 `update-grub` 日志里有没有 `Found Windows Boot Manager ...`，没有就在 `/etc/default/grub` 加 `GRUB_DISABLE_OS_PROBER=false` 并 `sudo apt install os-prober`。
- 纯配置改动，**不需要** `grub-install`，下次开机生效。
- 回滚：`sudo cp -a /etc/default/grub.bak-<时间> /etc/default/grub && sudo update-grub`。
