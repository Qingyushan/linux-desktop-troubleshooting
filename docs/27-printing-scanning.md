# 打印机加了没反应、扫描仪不识别

> 返回索引：[README](../README.md) ｜ 相关：[24-wifi-dns.md](24-wifi-dns.md)（网络打印机） ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 项 | 值 |
|---|---|
| CUPS | **2.4.16**，`cups.service` **active** |
| 相关包 | `cups`、`cups-bsd`、`cups-client`、`cups-common`、`cups-core-drivers`、`cups-browsed` 2.1.1 |
| mDNS | `avahi-daemon` **active**（网络打印机自动发现依赖它） |
| 扫描 | `sane-find-scanner`、`simple-scan` 已装 |
| 命令行 | `lpstat`、`lpinfo` 可用 |

---

## 1. 先看 CUPS 有没有"看到"打印机

```bash
lpstat -t
# 期望包含：
#   scheduler is running
#   system default destination: <打印机名>
#   device for <打印机名>: ipp://...
```

如果 `scheduler is running` 都没有：

```bash
systemctl status cups --no-pager | head -10
journalctl -u cups -b --no-pager | tail -30
```

---

## 2. 添加打印机：优先 driverless（IPP Everywhere）

现代网络/USB 打印机基本都支持 IPP Everywhere，**不需要厂商驱动**：

```bash
# 1. 看能不能发现
lpinfo -v
# 期望：network ipp://...、network dnssd://...、direct usb://...

# 2. 看支持的驱动
lpinfo -m | grep -i -E "everywhere|driverless" | head

# 3. 添加（driverless）
lpadmin -p MyPrinter -E -v "ipp://192.168.1.50/ipp/print" -m everywhere
lpoptions -d MyPrinter      # 设为默认
lpstat -p MyPrinter          # 期望：printer MyPrinter is idle
```

USB 打印机把 `ipp://` 换成 `usb://厂商/型号`，或者直接在 GNOME 设置 → 打印机里点添加（本质也是走这个流程）。

---

## 3. 打印任务卡住 / 队列不动

```bash
lpstat -o                    # 看排队任务
cancel -a MyPrinter          # 清空该打印机队列
cupsdisable MyPrinter && cupsenable MyPrinter   # 重置状态
```

任务卡在 "Processing" 且日志里有 `Unable to write` / `Filter failed`：

- 多半是驱动/PPD 不匹配 → 换成 `-m everywhere` 重加；
- 或 `/var/spool/cups` 磁盘满 → `df -h /var`。

---

## 4. 网络打印机找不到

| 检查 | 命令 | 期望 |
|---|---|---|
| mDNS 是否通 | `avahi-browse -rt _ipp._tcp` | 列出打印机 |
| 能否直连 | `nc -vz <IP> 631` | succeeded |
| 防火墙 | `sudo ufw status` | 631 未被拒 |

`avahi-browse` 无输出但 `nc` 通 → 用 IP 直连添加（`ipp://IP/ipp/print`），不依赖发现。

---

## 5. 扫描仪

```bash
sane-find-scanner          # 看 USB 设备层
scanimage -L               # 看 SANE 能识别的设备
# 期望：device `airscan:e0:...` is a ... scanner
```

- **网络扫描仪**：走 `airscan`/`escl`，依赖 mDNS + `sane-airscan`（`sudo apt install sane-airscan`）。
- **USB 扫描仪**：需要在 `scanner` / `lp` 组里：`sudo usermod -aG scanner,lp $USER`，**重新登录**后生效。
- **权限报错** `Permission denied` 基本就是组没生效。

---

## 6. 无效尝试

- **反复删了再加打印机**：先看 `lpstat -t` 与 CUPS 日志，否则只是重复同一个失败。
- **装厂商 .deb 驱动**：很多厂商包会替换 CUPS 自己的 filter，反而更不稳定；先试 `everywhere`。
- **以为 avahi 不必要**：网络打印机自动发现全靠它，`systemctl status avahi-daemon` 应该是 active。
- **用 root 跑 simple-scan**：图形应用不该用 root，权限问题应该加组解决。

---

## 7. 速查

| 症状 | 先看 |
|---|---|
| 添加打印机列表空 | `lpinfo -v`、avahi 状态 |
| 有打印机但打印无反应 | `lpstat -p`、`lpstat -o`、CUPS 日志 |
| 任务卡 Processing | `cancel -a`、`/var` 空间、PPD 是否 everywhere |
| 网络打印机离线 | `nc -vz IP 631`、防火墙 |
| 扫描仪不识别 | `scanimage -L`、`sane-find-scanner`、用户组 |

## 8. 经验

1. **`lpstat -t` 一屏定性**：调度器、默认打印机、设备 URI 全在里面。
2. **driverless（IPP Everywhere）优先**，省掉驱动的 80% 麻烦。
3. **mDNS/avahi 是网络打印机的隐形依赖**，它挂了表现为"以前能用的打印机突然消失"。
4. **扫描仪权限问题靠"加组 + 重新登录"**，`usermod` 后当前会话不会立即生效。
