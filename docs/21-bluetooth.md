# 蓝牙：连不上、连上没声音、麦克风不工作

> 返回索引：[README](../README.md) ｜ 相关：[19-audio-pipewire.md](19-audio-pipewire.md)（音频链路） ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 项 | 值 |
|---|---|
| BlueZ | **5.85**（`bluez`、`bluez-obexd`、`bluez-cups`） |
| 服务 | `bluetooth.service` **active** |
| 控制器 | `hci0`，MAC `04:7F:0E:05:13:9C`，**Soft/Hard blocked: no** |
| 已配对设备 | `OnePlus Buds Ace 3`（`C4:60:0A:EE:9C:F6`） |
| 音频侧 | PipeWire 1.6.2；耳机未连接时**没有** bluez sink |

---

## 1. 三类问题，先分清

| 类型 | 表现 | 主战场 |
|---|---|---|
| **连不上** | 配对失败、反复断开、设备不出现 | BlueZ / 控制器 / 射频 |
| **连上没声音** | 系统显示已连接，输出里没有耳机 | 音频 profile（A2DP） |
| **麦克风不能用 / 音质突然变差** | 一开麦音质掉成电话音 | 切到了 HFP/HSP，不是故障 |

---

## 2. 连不上：按这个顺序查

### 第 1 步：控制器状态

```bash
rfkill list bluetooth
# 期望：Soft blocked: no / Hard blocked: no

bluetoothctl show | head -12
# 期望：Powered: yes、Discovering: no
```

`Hard blocked: yes` = 物理开关/BIOS 禁用了无线；`Soft blocked: yes` = `rfkill unblock bluetooth`。

### 第 2 步：设备在不在、服务是否正常

```bash
systemctl status bluetooth --no-pager | head -5
bluetoothctl devices            # 已配对列表
dmesg | grep -i blue | tail -20 # 需要 sudo 时：sudo dmesg
```

常见内核报错：`hci0: command ... timeout`、`firmware` 加载失败 → 控制器/固件问题，不是耳机问题。

### 第 3 步：手动走一遍配对（比 GUI 可靠）

```bash
bluetoothctl
[bluetooth]# power on
[bluetooth]# agent on
[bluetooth]# default-agent
[bluetooth]# scan on          # 让耳机进入配对模式，等它出现
[bluetooth]# pair C4:60:0A:EE:9C:F6
[bluetooth]# trust C4:60:0A:EE:9C:F6
[bluetooth]# connect C4:60:0A:EE:9C:F6
[bluetooth]# scan off
[bluetooth]# quit
```

`trust` 很关键：不 trust 的话，耳机回连时可能被拒绝。

---

## 3. 连上没声音：看 A2DP 还是 HFP

蓝牙耳机有两种主要工作模式：

| 模式 | 用途 | 音质 | 麦克风 |
|---|---|---|---|
| **A2DP** | 听音乐 | 好（SBC/AAC/aptX 取决于耳机与 BlueZ） | 不可用 |
| **HFP/HSP** | 通话 | 差（电话音） | 可用 |

**一旦某个应用打开麦克风，系统可能整体切到 HFP**，于是"听歌突然变糊"——这不是坏了。

### 确认当前 profile

```bash
wpctl status | sed -n '/Audio/,$p' | grep -i -B2 -A4 blue
# 或看设备详情（id 用 wpctl status 里的数字）
wpctl inspect <id> | grep -E "profile|codec|api.bluez"
```

### 切 profile

```bash
wpctl inspect <device-id> | grep -A30 profiles   # 看可选 profile 及编号
wpctl set-profile <device-id> <profile-index>    # 例如 a2dp-sink
```

### 没有 bluez sink 时

1. `wpctl status` 里 Audio → Devices 应出现耳机；
2. 没有的话，`systemctl --user restart wireplumber` 后重连；
3. 仍没有：`bluetoothctl disconnect` 再 `connect`；必要时 `remove` 后重配。

---

## 4. 反复断连 / 被手机抢

- **双设备同时连接**：耳机常同时记着手机和电脑，手机来电会抢走。解决：在手机端断开，或耳机进入"只连一台"模式。
- **省电策略**：`/etc/bluetooth/main.conf` 里 `[Policy]` 段可调 `AutoEnable=true`、`ReconnectAttempts`；改完 `systemctl restart bluetooth`。
- **USB 蓝牙 dongle 与 Wi-Fi 2.4G 干扰**：把 dongle 插到远离 USB 3.0 口的延长线上，能显著减少断连。

---

## 5. 无效尝试

- **只重启耳机**：先看 `bluetoothctl show` 的 `Powered`，控制器没开怎么重启耳机都没用。
- **反复删除再配对但不 remove**：旧的配对记录还在，会一直连到旧 key。正确做法是 `bluetoothctl remove <MAC>` 再重新配。
- **重装 bluez**：99% 的情况是 profile / 射频 / 耳机模式问题，不是软件包坏了。
- **在"设置 → 蓝牙"里死磕**：GUI 隐藏了 profile 和 trust，命令行能看到更多信息。

---

## 6. 速查

| 症状 | 先看 | 处理 |
|---|---|---|
| 设备列表里没有耳机 | 耳机是否在配对模式、`scan on` | 重新进入配对模式再扫 |
| 配对成功但连不上 | `trust`、`bluetoothctl info` | `trust` + `connect` |
| 连上了没声音 | `wpctl status` 有无 bluez sink | 重连 / 重启 wireplumber |
| 音质突然变电话音 | 是否切到 HFP | 关掉占用麦克风的应用，切回 A2DP |
| 频繁断连 | rfkill、USB 口干扰、手机抢占 | 换口 / 关手机蓝牙 / 调 main.conf |
| 开机不自动连 | `AutoEnable`、设备是否 trust | 见第 4 节 |

## 7. 经验

1. **命令行优先**：`bluetoothctl` 能看到 `trust`、`profile`、`Powered` 这些 GUI 不显示的状态。
2. **"没声音"和"音质差"是两件事**：前者查 sink，后者查 A2DP/HFP。
3. **`rfkill` 与 `Powered` 是两个独立开关**：一个管射频，一个管协议栈，都得是开的。
4. **`remove` 再配比反复 `connect` 有效**；旧配对记录是隐形故障源。
