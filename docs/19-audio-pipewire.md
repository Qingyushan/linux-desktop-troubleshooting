# 没声音：从「哪个环节断了」到 PipeWire 的正确排查顺序

> 返回索引：[README](../README.md) ｜ 相关：[21-bluetooth.md](21-bluetooth.md)（蓝牙耳机） ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 项 | 值 |
|---|---|
| 会话 | Wayland / GNOME 50 |
| 声音服务 | PipeWire **1.6.2** + WirePlumber；`pipewire-pulse.service` 运行中 |
| 声卡 | `内置音频`（Realtek ALC269VC）+ `GP106 High Definition Audio Controller`（NVIDIA HDMI） |
| 默认输出 | `内置音频 模拟立体声`（sink id 58） |
| 命令行工具 | `wpctl`、`pw-cli` 有；**`pactl` 没装**（属于 pulseaudio-utils） |

> 这一条很关键：网上大量教程用 `pactl`，本机没有；**用 `wpctl` 替代**，语义基本一一对应。

---

## 1. 先把"没声音"分成三类

不分类就开始乱试，是最常见的浪费时间方式：

| 类型 | 判断方法 | 大概率在哪一层 |
|---|---|---|
| **全系统无声** | 系统提示音、浏览器、播放器全没声 | 默认 sink、静音、声卡 profile |
| **只有某个应用无声** | 别的应用正常 | 该应用的 stream 挂错 sink / 被静音 |
| **只有某个设备无声** | 切到内置有声，HDMI/蓝牙没声 | 该设备的 profile、连线、codec |

---

## 2. 定位链条（按顺序，不要跳）

### 第 1 步：默认 sink 是谁

```bash
wpctl status
# 看 Audio → Sinks 里带 * 的那一行，例如：
#  *   58. 内置音频 模拟立体声   [vol: 0.50]
```

期望：带 `*` 的 sink 就是你想要的设备。

### 第 2 步：应用的流挂到哪

```bash
wpctl status | sed -n '/Streams:/,$p'
# 例如：74. Firefox → 78. output_FL > ALC269VC Analog:playback_FL [active]
```

如果 Firefox 的流挂在 `GP106 HDMI` 上而显示器没喇叭，就是"设备选错"——在 GNOME 声音面板或 `wpctl` 里改。

### 第 3 步：看这个 sink 是不是静音/音量为 0

```bash
wpctl inspect @DEFAULT_AUDIO_SINK@ | grep -E "mute|volume|node.name"
```

### 第 4 步：看设备 profile

```bash
wpctl inspect 52 | grep -A20 "profiles"     # 52 = 设备 id，按 wpctl status 里的数字替换
```

HDMI 设备通常有多个 profile（`output:hdmi-stereo`、`output:hdmi-surround`…），选错就是"有设备没声音"。

### 第 5 步：看服务日志

```bash
journalctl --user -b -u pipewire -u wireplumber --no-pager | tail -40
```

常见关键字：`no node available`、`device busy`、`failed to open`、`profile`。

---

## 3. 常用命令（`wpctl` 版）

| 目的 | 命令 |
|---|---|
| 看全局 | `wpctl status` |
| 设默认输出 | `wpctl set-default <sink-id>` |
| 调音量 | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.6` |
| 静音开关 | `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` |
| 看某节点详情 | `wpctl inspect <id>` |
| 切设备 profile | `wpctl set-profile <device-id> <profile-index>` |
| 看原始图 | `pw-cli ls Node` / `pw-dump` |

> 想用 `pactl` 的话装 `pulseaudio-utils`（它只是客户端，不会把 PipeWire 换掉），但没必要，`wpctl` 够用。

---

## 4. HDMI（NVIDIA）没声音

本机有两块"声卡"：主板的内置音频，和显卡通过 HDMI 送出的音频（`GP106 High Definition Audio Controller`）。

- **没接显示器 / 显示器没开**：HDMI sink 根本不会出现，这是正常的，不是故障。
- **接了但没声**：`wpctl status` 里 HDMI 设备存在，但 profile 可能是 `off`；切到 `output:hdmi-stereo` 再试。
- **NVIDIA 专有驱动**：音频走 PCI，与显卡电源状态有关；笔记本接 HDMI 后 `nvidia-smi` 显示显卡休眠时偶发无声，动一下图形负载通常恢复。

---

## 5. 爆音、延迟、切换设备后无声

| 现象 | 原因 | 处理 |
|---|---|---|
| 爆音/咔哒声 | 采样率或 quantum 抖动 | `pw-metadata -n settings 0 clock.force-quantum 512`（临时） |
| 切换输出后无声 | 应用还挂在旧 sink | 重启该应用，或 `wpctl status` 里确认流已迁移 |
| 只有 44.1k 的应用爆音 | 重采样 | 同上，调 quantum 或允许 PipeWire 重采样 |
| 待机回来没声 | 声卡电源管理 | `journalctl` 看是否 `snd_hda_intel` 重新枚举；必要时重启 `wireplumber` |

---

## 6. 无效尝试（我都见过）

- **装回 PulseAudio**：`pipewire-pulse` 已经在提供 PulseAudio 协议，装真正的 PA 会抢 socket，结果是"更没声音"。
- **删 `~/.config/pulse`**：PipeWire 下这目录基本没用；配置在 `~/.config/pipewire/` 与 WirePlumber 的 `~/.local/state/wireplumber/`。
- **反复点 GNOME 声音面板**：面板只是 `wpctl` 的 GUI，底层不通点一万次也没用。
- **把默认 sink 设成 "auto"**：没有这种设置；默认 sink 是显式 id。

---

## 7. 速查

| 症状 | 先看 |
|---|---|
| 全都没声 | `wpctl status` 的 `*` sink、`mute`、音量 |
| 只有一个应用没声 | 该 stream 挂的 sink（`wpctl status` Streams 段） |
| HDMI 没声 | HDMI 设备是否存在、profile 是否 `off` |
| 蓝牙耳机没声 | 见 [21-bluetooth.md](21-bluetooth.md)：A2DP vs HFP |
| 切换后没声 | 重启应用，确认 stream 迁移 |
| 待机后没声 | `wireplumber` 状态、`snd_hda_intel` 日志 |

## 8. 经验

1. **先看 sink，再看应用，再看设备 profile**——顺序反了就会在"应用设置"里空转。
2. **`wpctl status` 一屏信息量最大**：默认设备、每个应用流、设备 profile 都在里面。
3. **没有 `pactl` 不是问题**，`wpctl` 是 PipeWire 原生工具，语义更直接。
4. **HDMI 音频"没有设备"通常是正常的**（显示器没接），不要为此重装驱动。
