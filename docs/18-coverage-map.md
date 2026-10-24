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

### F. 方法与索引

| 内容 | 文档 |
|---|---|
| 排障纪律、我犯过的错 | [lessons.md](lessons.md) |
| 未解决 / 后续 | [15-unresolved.md](15-unresolved.md) |
| 全仓库索引 | [README](../README.md) |

---

## 2. 空白区（还没写，但迟早会踩）

按「发生概率 × 排错成本」排序，前五个建议优先补：

| 优先级 | 领域 | 典型症状 | 为什么值得写 |
|---|---|---|---|
| ★★★ | **音频** | 突然没声音、输出设备选错、HDMI/蓝牙切换后静音 | 发生频率最高；PipeWire 的 `pactl`/`wpctl` 与 GNOME 声音面板关系容易绕晕 |
| ★★★ | **屏幕共享 / 录屏（Wayland）** | 会议软件共享黑屏、OBS 抓不到窗口 | Wayland 下走 portal + PipeWire，和 X11 时代完全不同，网上老教程全是错的 |
| ★★★ | **蓝牙** | 耳机连上没声音、A2DP/HFP 来回跳、断连 | 与音频强相关，常被误判成"声卡坏了" |
| ★★☆ | **系统更新后的内核/显卡** | 更新后黑屏、掉到 llvmpipe、nvidia 模块没编 | 低频但**致命**，一旦发生机器进不了图形界面 |
| ★★☆ | **电源 / 续航 / 合盖休眠** | 合盖不睡、睡死、耗电快 | 笔记本常见；涉及 `systemd-logind` 与内核参数 |
| ★★☆ | **Wi-Fi / DNS** | 连不上、能 ping IP 不能解析域名 | 排查路径固定（`nmcli` → `resolvectl` → 路由），适合写成清单 |
| ★☆☆ | **Flatpak / Snap 沙箱权限** | 应用读不到 `~/Documents`、输入法不工作 | 本机 Firefox/Thunderbird 是 snap，早晚遇到 |
| ★☆☆ | **字体渲染** | 中文发虚、粗体缺失、界面字体不一致 | 涉及 fontconfig 与 GNOME 字体设置，容易改乱 |
| ★☆☆ | **打印 / 扫描** | 打印机添加失败、扫描仪不识别 | 低频，但 CUPS 日志对新手不友好 |
| ★☆☆ | **触摸板 / 手势** | 三指手势、轻触点击、滚动方向 | 偏好类，非故障类 |

---

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
