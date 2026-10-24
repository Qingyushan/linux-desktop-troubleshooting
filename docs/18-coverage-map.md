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

## 2.1 仍然空白（按领域分组，附本机现状）

判断依据是「本机实际有、或早晚会遇到」；单纯"别人可能会踩"的不列。优先级：★★★ 值得先写 / ★★☆ 有场景再写 / ★☆☆ 暂不写。

### A. 显示与远程

| 优先级 | 领域 | 典型症状 | 第一篇该写什么 | 本机现状 |
|---|---|---|---|---|
| ★★★ | **远程桌面（RDP/VNC）** | 想从另一台机器连进来；Wayland 下 VNC 方案失效 | `gnome-remote-desktop` + `grdctl` 开启 RDP、gnome-connections 连接、与旧 VNC 的区别 | **已装** `gnome-remote-desktop`（| `grdctl` 可用），尚未写过 |
| ★★☆ | **外接显示器 / 多屏缩放** | 接上显示器后缩放不一致、窗口跑屏、热插拔不识别 | `gnome-monitor-config` / Mutter 的 fractional scaling、`xrandr` 在 Wayland 下的边界 | 5 个 DRM 连接器，**只有 eDP-1 连接**（未接外屏） |
| ★☆☆ | **显示器色温 / 夜灯 / HDR** | 偏色、夜间刺眼、HDR 不生效 | GNOME 夜灯、`colord` 配置、HDR 需要合成器+显卡支持 | 未遇到 |

### B. 存储与备份

| 优先级 | 领域 | 典型症状 | 第一篇该写什么 | 本机现状 |
|---|---|---|---|---|
| ★★★ | **系统备份与快照** | 想回滚一次坏更新 / 误删文件 | ext4 下用 `rsync` 做增量备份、`timeshift` 的取舍；btrfs 快照为何不适用本机 | 根分区 **ext4**，无 timeshift、无 btrfs；`rsync` 有 |
| ★★☆ | **磁盘健康（SMART）** | 怀疑盘要坏、读写卡顿 | `smartctl -a`、NVMe 健康字段、`badblocks` 的正确用法（别对 SSD 跑） | **smartctl 未装** |
| ★★☆ | **磁盘空间与 inode** | 明明有空间却写不进去 | `df -h` vs `df -i`、`du` 找大目录、`ncdu`、日志/缓存占用 | 未遇到 |
| ★☆☆ | **外置盘热插拔策略** | 拔出前忘记卸载导致脏卷 | `udisksctl`/`eject`、`sync`、NTFS 脏标记的后果（已由 [16](16-windows-dirty-volume.md) 部分覆盖） | 已有 G1 常驻挂载 |

### C. 系统维护

| 优先级 | 领域 | 典型症状 | 第一篇该写什么 | 本机现状 |
|---|---|---|---|---|
| ★★★ | **系统更新策略** | 想只装安全更新、或不想被内核更新打断 | `unattended-upgrades` 配置、`apt-mark hold` 内核/nvidia、`apt list --upgradable` 的先看什么 | 未配置 |
| ★★☆ | **日志与 journal 瘦身** | `/var/log` 涨到几 GB | `journalctl --vacuum-size`、`SystemMaxUse`、rsyslog 与 journald 的关系 | journal 当前 **72 MB** |
| ★★☆ | **时间同步与证书** | 时间漂移导致 TLS/证书报错 | `timedatectl`、NTP 源、RTC 与 UTC 的关系 | 正常（`Asia/Shanghai`，RTC=UTC） |
| ★☆☆ | **包回滚 / 降级** | 升级后某包行为变了 | `apt install pkg=version`、`apt-mark hold`、`/var/cache/apt/archives` | 部分由 [22](22-nvidia-kernel-update.md) 覆盖 |

### D. 硬件

| 优先级 | 领域 | 典型症状 | 第一篇该写什么 | 本机现状 |
|---|---|---|---|---|
| ★★☆ | **温度 / 风扇 / 降频** | 风扇狂转、性能掉、烫手 | `lm-sensors` 安装与 `sensors`、`thermald`、`nvidia-smi` 温度、`cpupower` | **lm-sensors 未装** |
| ★★☆ | **电池健康** | 续航突然腰斩 | `upower -i` 的 capacity/cycles、`/sys/class/power_supply/BAT0/`、校准 | 有 `BAT0`，未记录健康值 |
| ★☆☆ | **键盘背光 / 快捷键** | Fn 键无效、多媒体键不对 | `libinput`、`/usr/lib/udev/hwdb.d`、GNOME 快捷键冲突 | 未遇到 |
| ★☆☆ | **指纹 / 摄像头** | 指纹录入失败、摄像头黑 | `fprintd`、`libcamera`、Wayland 下摄像头权限 | 未遇到 |

### E. 账户与安全

| 优先级 | 领域 | 典型症状 | 第一篇该写什么 | 本机现状 |
|---|---|---|---|---|
| ★★☆ | **密钥环 / 密码提示循环** | 登录后反复弹"解锁密钥环" | GNOME Keyring 与 PAM 的衔接、`seahorse` 重置、autologin 的影响 | 未遇到 |
| ★★☆ | **SSH / GPG 密钥** | 新机器恢复密钥、ssh-agent 不自动加载 | 密钥文件权限、`ssh-agent` 与 systemd user service、GPG 与 git 签名 | 未整理 |
| ★☆☆ | **防火墙** | 想确认 631/3389 等端口是否放行 | `ufw` 基础规则、`ss -ltnp` 看监听 | 未确认状态 |

### F. 开发环境

| 优先级 | 领域 | 典型症状 | 第一篇该写什么 | 本机现状 |
|---|---|---|---|---|
| ★★☆ | **容器 / 虚拟机** | 想跑 Docker 或 KVM，与 snap/AppArmor 冲突 | `docker` 与 `podman` 取舍、cgroup v2、AppArmor profile、`virt-manager` | **均未安装** |
| ★★☆ | **代理 / VPN** | 部分应用不走系统代理 | `HTTP_PROXY` 与 GNOME 代理、`proxychains`、WireGuard/OpenVPN 与 resolved 的 DNS 泄漏 | 本机有 S302 中间人场景（[01](01-firefox-github-cert.md)） |
| ★☆☆ | **语言运行时 / 版本管理** | 多版本 Node/Python 并存冲突 | `mise`/`asdf`/`pyenv` 的 PATH 顺序、与系统包的边界 | 未整理 |
| ★☆☆ | **专业音频（JACK/低延迟）** | 录音爆音、延迟高 | PipeWire 的 JACK 兼容层、`pw-jack`、realtime 权限 | 未涉及 |

> 这些条目的共同点：**本机要么没装对应软件，要么还没踩到**。写文档的价值在于"下次真遇到时不用从零搜"，所以优先级按「会不会很快遇到」排，而不是按"话题是否热门"排。

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
