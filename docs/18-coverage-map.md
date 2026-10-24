# 问题覆盖面地图：这个仓库管到哪、还缺什么

> 返回索引：[README](../README.md) ｜ 相关：[lessons.md](lessons.md)（方法）、[15-unresolved.md](15-unresolved.md)（未解决项）

这份不是排障教程，是**地图**：一页看清"哪些坑已经写过、哪些还没写"。新增文档时先看这里，避免重复造一篇，也避免以为覆盖了其实漏着。

---

## 1. 已覆盖的问题（按领域）

### A. 证书 / TLS / 中间人

| 问题 | 文档 | 关键结论 |
|---|---|---|
| Firefox 打不开 GitHub（`SEC_ERROR_UNKNOWN_ISSUER`） | [01](01-firefox-github-cert.md) | Firefox 用独立 NSS 库，系统 CA 管不到 |
| Steam 商店 `-202 Invalid SSL Certificate` | [03](03-steam-cert-error-202.md) | CEF 用 `~/.pki/nssdb`，且新版 certutil 导入的条目旧版读不了 |

### B. 软件安装与打包

| 问题 | 文档 | 关键结论 |
|---|---|---|
| QQ / 微信 / Steam 安装 | [02](02-install-qq-wechat-steam.md) | deb 包与依赖、首次登录 |
| DSH AppImage → deb | [07](07-dsh-deb-switch.md) | 同版本不同打包，行为可能完全不同 |
| LX Music 自定义音源 | [04](04-lx-music.md) | 源格式与风险 |

### C. DSH 桌面端

| 问题 | 文档 | 关键结论 |
|---|---|---|
| 画面冻结、只刷新首帧 | [05](05-dsh-render-freeze.md) | 不是 GPU 光栅化问题，是呈现/帧同步层 |
| 停靠栏/应用菜单图标空白 | [06](06-dsh-dock-icon-blank.md) | GNOME Shell 按图标名缓存，换新名字 + 用户级覆盖 |
| 功能体检清单 | [08](08-dsh-feature-check.md) | 逐项验证（托盘、宠物、`dsh://`、inotify…） |
| 缩放、插件去重、侧栏空按钮、dsh-ui 卡片 | [dsh-profile-tuning](dsh-profile-tuning.md) | 125% 缩放、GNOME 网格扩展失败的记录、genui 渲染器依赖 |

### D. 磁盘与文件系统

| 问题 | 文档 | 关键结论 |
|---|---|---|
| Steam/Proton 在 NTFS 库上失败 | [09](09-steam-proton-ntfs.md) | ntfs3 并发建链接失败 → 换 ntfs-3g |
| Windows 分区挂载失败（dirty 卷） | [16](16-windows-dirty-volume.md) | 快速启动=混合休眠，留 dirty 标记；不要硬清 |
| G1 开机自动挂载 / 双挂载 / 驱动选择 | [17](17-g1-automount.md) | fstab + nofail + ntfs-3g；udisks 与 fstab 会打架 |

### E. 桌面体验与系统服务

| 问题 | 文档 | 关键结论 |
|---|---|---|
| QQ/微信/DSH 开机静默启动 | [10](10-quiet-autostart.md) | GNOME 扩展按 pid 匹配 + 周期扫描；`app_id` 提交晚于 `window-created` |
| Rime 雾凇拼音 | [11](11-rime-ime.md) | 词库、候选数、中英切换 |
| Variety 壁纸轮换 | [12](12-variety-wallpaper.md) | 避开 GNOME 自己的壁纸缓存 |
| GRUB 菜单等待时间（双系统） | [13](13-daily-tips.md) | `30_os-prober` 会兜底改写 timeout，只改 `/etc/default/grub` 不一定生效 |
| 日常命令与小习惯 | [13](13-daily-tips.md)、[14](14-appendix-commands.md) | 检查命令、日志位置 |
| 没声音 / 设备切换（PipeWire） | [19](19-audio-pipewire.md) | `wpctl status` 三步定位；HDMI 无设备常属正常 |
| Wayland 屏幕共享 / 录屏黑屏 | [20](20-wayland-screenshare.md) | portal + PipeWire 链路；X11 工具在 Wayland 抓不到 |
| 蓝牙连不上 / 连上没声音 | [21](21-bluetooth.md) | A2DP vs HFP；rfkill 与 Powered 是两个开关 |

### F. 方法与索引

| 内容 | 文档 |
|---|---|
| 排障纪律、我犯过的错 | [lessons.md](lessons.md) |
| 未解决 / 后续 | [15-unresolved.md](15-unresolved.md) |
| 全仓库索引 | [README](../README.md) |

---

## 2. 系统层（19–28，已补齐）

原来列在"空白区"的问题，现已按「先实测、再写」补齐：

| 领域 | 文档 | 本机实测依据 |
|---|---|---|
| 音频（PipeWire） | [19](19-audio-pipewire.md) | PipeWire 1.6.2、`pactl` 未装、ALC269VC + NVIDIA HDMI |
| Wayland 屏幕共享 / 录屏 | [20](20-wayland-screenshare.md) | portal 1.21.1 / -gnome 50.0、`pipewiresrc` 可用 |
| 蓝牙 | [21](21-bluetooth.md) | bluez 5.85、`hci0` 未 rfkill、已配对 OnePlus Buds Ace 3 |
| 系统更新后黑屏 / 掉驱动 | [22](22-nvidia-kernel-update.md) | GTX 1060 Mobile + nvidia 580.178.04、Secure Boot enabled、内核 7.0.0-38 |
| 电源与休眠 | [23](23-power-suspend.md) | `mem_sleep = s2idle [deep]`、logind 无覆盖、powerprofiles = performance |
| Wi-Fi 与 DNS | [24](24-wifi-dns.md) | `wlp3s0` 已连、systemd-resolved stub、DNS 10.15.3.223 |
| Snap / Flatpak 沙箱 | [25](25-flatpak-snap.md) | snapd 2.77.1、Firefox/Thunderbird 为 snap、flatpak 未装 |
| 中文字体 | [26](26-fonts.md) | 604 个字体 / 89 个中文；`fc-match sans-serif:lang=zh` → **CJK JP** |
| 打印 / 扫描 | [27](27-printing-scanning.md) | CUPS 2.4.16 active、avahi active、simple-scan 已装 |
| 触摸板 / 手势 | [28](28-touchpad.md) | tap-to-click=true、natural-scroll=true、libinput quirks 目录 |

## 2.1 仍然空白（优先级较低）

| 领域 | 典型症状 | 建议 |
|---|---|---|
| **远程桌面 / VNC** | 想从别的机器连进来 | Wayland 下走 `gnome-remote-desktop` + RDP，与 VNC 方案不同 |
| **多显示器缩放** | 外接屏与内置屏缩放不一致 | Mutter 的 fractional scaling，需要专门写 |
| **系统备份 / 快照** | 想回滚一次坏更新 | Timeshift / btrfs 快照，本机 ext4 需 rsync 方案 |
| **时间同步** | 时间漂移导致证书报错 | `timedatectl`、NTP 源 |
| **虚拟机 / 容器** | KVM、Docker 与 snap 冲突 | 涉及 cgroup 与 AppArmor |
| **专业音频** | 低延迟录音、JACK | PipeWire 的 JACK 兼容层 |

## 3. 这仓库**不打算**覆盖的

- 发行版级的大改（换桌面环境、换 init）。
- 硬件维修/BIOS 刷写。
- Windows 侧的排障（只在"它影响 Linux 挂载"时提及，如 [16](16-windows-dirty-volume.md)）。

---

## 4. 新增一篇的约定

1. 文件：`docs/NN-<slug>.md`，编号接续，不改旧编号。
2. README 目录表加一行（问题名 + 文档链接 + 相关脚本）。
3. 结构统一：**症状 → 怎么定位 → 无效尝试（重要）→ 最终方案与代价 → 经验**。
4. 页首写：`> 返回索引：[README](../README.md) ｜ 原始位置 ｜ 相关脚本`。
5. 同一主题的不同层次**允许并存**（如 09 讲 Proton 失败、17 讲挂载），但要在页首互相链接，别复制整段。

---

## 5. 一句话

覆盖面的目标不是"文档多"，而是**下次出问题时能在一页里找到入口**：现象对得上 → 点进去 → 有命令、有期望输出、有回滚。缺的那几块，按上面的优先级补就行。
