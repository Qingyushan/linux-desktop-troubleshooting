# 电源与休眠：合盖不睡、睡死、续航变短

> 返回索引：[README](../README.md) ｜ 相关：[22-nvidia-kernel-update.md](22-nvidia-kernel-update.md)（睡醒黑屏常与显卡有关） ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 项 | 值 |
|---|---|
| 机型 | 笔记本（NVIDIA GP106M + 内置音频 ALC269VC） |
| 电池 | `BAT0`，电源 `AC0` |
| 当前电源配置 | `/sys/power/mem_sleep` = **`s2idle [deep]`**（已选 `deep`） |
| logind | `/etc/systemd/logind.conf` 只有 `[Login]` 段，**没有** `HandleLidSwitch` 覆盖 |
| 电源管理 | `power-profiles-daemon` 在，当前 `powerprofilesctl get` = **`performance`**；**未装 TLP** |

---

## 1. 三个不同的问题，别混

| 问题 | 表现 | 主战场 |
|---|---|---|
| **合盖行为不对** | 合盖不休眠 / 合盖直接关机 | `systemd-logind` + GNOME 电源设置 |
| **睡不进去 / 睡死** | 点击"挂起"黑屏但风扇还转、或睡醒黑屏 | 内核 `mem_sleep`、显卡/网卡唤醒 |
| **续航短** | 同一块电池用得比 Windows 快 | 电源配置、后台进程、独显常开 |

---

## 2. 合盖行为：logind 与 GNOME 谁说了算

```bash
grep -vE '^#|^$' /etc/systemd/logind.conf
# 本机输出只有 [Login] —— 说明没做任何覆盖，全用默认（合盖 = suspend）

# GNOME 侧：
gsettings get org.gnome.settings-daemon.plugins.power lid-close-ac-action
gsettings get org.gnome.settings-daemon.plugins.power lid-close-battery-action
```

**关系**：GNOME 会给 logind 发 inhibit，实际行为由 GNOME 设置决定；如果你改了 `logind.conf` 却"没生效"，先看 GNOME 这两项。

想彻底自己管（比如合盖不休眠），在 `/etc/systemd/logind.conf` 写：

```ini
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

然后 `sudo systemctl restart systemd-logind`（注意：会短暂影响已有会话）。

---

## 3. 睡不进去 / 睡死

### 先确认睡眠模式

```bash
cat /sys/power/mem_sleep
# 本机：s2idle [deep] → 方括号是当前值，deep = 真·挂起到内存（省电）
# 如果显示 [s2idle] → 浅睡眠，耗电快、容易被吵醒

# 切到 deep（本机已是 deep）：
echo deep | sudo tee /sys/power/mem_sleep
# 永久：内核参数 mem_sleep_default=deep
```

### 睡死/睡醒黑屏怎么查

```bash
journalctl -b -1 | grep -iE "suspend|hibernat|PM: " | tail -30
# 关键行：
#   PM: suspend entry (deep)      —— 进睡眠
#   PM: suspend exit              —— 醒来
#   若只有 entry 没有 exit，或 exit 后有 NVRM/Xid 报错 → 显卡唤醒失败
```

NVIDIA 笔记本的经典组合：`NVRM: Xid` / `nvidia_drm` 相关报错 → 睡醒黑屏。缓解方式：

- 内核参数加 `nvidia.NVreg_PreserveVideoMemoryAllocations=1`（580 驱动支持）；
- 或启用 `nvidia-suspend.service` / `nvidia-resume.service`（`systemctl status nvidia-suspend` 看有没有）。

### 睡醒后网络/音频没了

`systemctl restart NetworkManager` / `systemctl --user restart wireplumber` 通常能救回来；反复发生再看具体驱动。

---

## 4. 续航

```bash
powerprofilesctl get            # performance / balanced / power-saver
powerprofilesctl set balanced   # 或 power-saver
upower -i /org/upower/devices/battery_BAT0 | grep -E "percentage|time to empty|energy-rate"
```

本机当前是 `performance`——插电时合理，拔电后建议 `balanced`。

**独显常开的坑**：NVIDIA 笔记本如果 `nvidia-smi` 显示显卡一直有进程占用，功耗会明显上去。查：

```bash
nvidia-smi --query-compute-apps=pid,process_name --format=csv
```

**不建议**装 TLP + power-profiles-daemon 并存，两者会抢电源策略；本机没装 TLP，保持现状即可。

---

## 5. 无效尝试

- **只看 `logind.conf` 就下结论**：GNOME 的 inhibit 会盖过它。
- **删 `/etc/systemd/sleep.conf`**：默认值通常就是对的，问题在硬件唤醒而非配置。
- **`pm-suspend`（pm-utils）**：已过时，与 systemd 的睡眠流程冲突。
- **合盖直接断电**：NTFS 盘（G1）会留 dirty 标记，下次挂载失败，见 [16](16-windows-dirty-volume.md)。

---

## 6. 速查

| 症状 | 先看 |
|---|---|
| 合盖不休眠 | `gsettings ... lid-close-ac-action`、`logind.conf` |
| 睡下去立刻醒 | `journalctl -b -1` 里的 wakeup 源 |
| 睡醒黑屏（NVIDIA） | `NVRM`/`Xid` 日志、`nvidia-suspend` 服务 |
| 睡醒没声音 | `systemctl --user restart wireplumber`（见 [19](19-audio-pipewire.md)） |
| 续航短 | `powerprofilesctl get`、独显占用、后台进程 |

## 7. 经验

1. **合盖行为是 GNOME 与 logind 两层的合力**，改一层可能"看起来没生效"。
2. **`mem_sleep` 的方括号才是生效值**，与配置文件里的写法无关。
3. **睡醒黑屏先怀疑显卡唤醒**，不是桌面环境坏了。
4. **合盖断电是 NTFS 的天敌**：G1 上的 Steam 库会留脏标记，开机挂载失败。
