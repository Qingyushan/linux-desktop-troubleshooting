# Ubuntu 26.04 + NVIDIA 桌面踩坑记录

> 记录时间：2026-10-23 起（持续更新）  
> 机器：Ubuntu 26.04.1 LTS / GNOME 50.1 (Wayland) / NVIDIA GTX 1060 Mobile (580.178.04) + Intel HD 630  
> 涉及：Firefox、Steam / Proton、QQ、微信、LX Music、Rime、Variety、DSH 桌面端（Tauri + WebKitGTK）

这份仓库按**问题**组织，每个问题一篇文档：症状 → 怎么定位 → 哪些尝试无效 → 最终方案与代价。

## 目录

| # | 问题 | 文档 | 相关脚本 |
| - | - | - | - |
| 1 | Firefox 打开 GitHub 报 `SEC_ERROR_UNKNOWN_ISSUER` | [01-firefox-github-cert.md](docs/01-firefox-github-cert.md) | [fix-firefox-s302-ca.sh](scripts/fix-firefox-s302-ca.sh) |
| 2 | 安装 QQ、微信、Steam | [02-install-qq-wechat-steam.md](docs/02-install-qq-wechat-steam.md) | — |
| 3 | Steam 商店 `-202 Invalid SSL Certificate` | [03-steam-cert-error-202.md](docs/03-steam-cert-error-202.md) | [fix-steam-s302-ca.sh](scripts/fix-steam-s302-ca.sh) |
| 4 | LX Music 与自定义音源 | [04-lx-music.md](docs/04-lx-music.md) | — |
| 5 | DSH 桌面端画面冻结（只刷新首帧） | [05-dsh-render-freeze.md](docs/05-dsh-render-freeze.md) | [restart-dsh.sh](scripts/restart-dsh.sh)、[set-scale.py](scripts/set-scale.py) |
| 6 | DSH 停靠栏 / 应用菜单图标空白 | [06-dsh-dock-icon-blank.md](docs/06-dsh-dock-icon-blank.md) | [fix-dsh-icon.sh](scripts/fix-dsh-icon.sh) |
| 7 | 切换到 .deb 与清理 | [07-dsh-deb-switch.md](docs/07-dsh-deb-switch.md) | — |
| 8 | 功能体检（deb 版） | [08-dsh-feature-check.md](docs/08-dsh-feature-check.md) | — |
| 9 | **Steam / Proton 在 NTFS 库上「兼容性工具失败」、启动 2 秒退出** | [09-steam-proton-ntfs.md](docs/09-steam-proton-ntfs.md) | [switch-g1-to-ntfs3g.sh](scripts/switch-g1-to-ntfs3g.sh)、[fix-steam-ntfs-library.sh](scripts/fix-steam-ntfs-library.sh) |
| 10 | QQ / 微信 / DSH 开机「安静」自启（窗口最小化到托盘） | [10-quiet-autostart.md](docs/10-quiet-autostart.md) | [install-quiet-startup.sh](scripts/install-quiet-startup.sh)、[gnome-extension/](gnome-extension/) |
| 11 | Rime 雾凇拼音输入法 | [11-rime-ime.md](docs/11-rime-ime.md) | — |
| 12 | Variety 壁纸轮换 | [12-variety-wallpaper.md](docs/12-variety-wallpaper.md) | — |
| 13 | 系统小习惯与日常命令 | [13-daily-tips.md](docs/13-daily-tips.md) | — |
| 14 | 附录：常用检查命令 | [14-appendix-commands.md](docs/14-appendix-commands.md) | — |
| 15 | 尚未解决 / 后续 | [15-unresolved.md](docs/15-unresolved.md) | — |
| 16 | **Windows 分区（176 GB 卷）在「文件」里挂载失败** | [16-windows-dirty-volume.md](docs/16-windows-dirty-volume.md) | —（fstab 只读挂载） |
| 17 | **G1 盘开机自动挂载；ntfs-3g 与 ntfs3 怎么选** | [17-g1-automount.md](docs/17-g1-automount.md) | —（fstab 挂载） |
| 18 | **问题覆盖面地图：哪些坑写了、哪些还没写** | [18-coverage-map.md](docs/18-coverage-map.md) | — |
| 19 | **没声音：PipeWire 的正确排查顺序** | [19-audio-pipewire.md](docs/19-audio-pipewire.md) | — |
| 20 | **Wayland 屏幕共享 / 录屏黑屏** | [20-wayland-screenshare.md](docs/20-wayland-screenshare.md) | — |
| 21 | **蓝牙：连不上 / 连上没声音 / 麦克风** | [21-bluetooth.md](docs/21-bluetooth.md) | — |
| — | DSH 档案调优（缩放、插件去重、侧栏空按钮） | [dsh-profile-tuning.md](docs/dsh-profile-tuning.md) | [dsh/profile-config/](dsh/profile-config/) |
| — | **经验总结（方法、教训、我犯过的错）** | [lessons.md](docs/lessons.md) | — |

> 第 11～13 篇不是排障，而是把这次装好的软件调成“顺手”的配置。按软件分开，命令可以直接复制。

## 快速结论（TL;DR）

1. **HTTPS 报错先查"谁在中间人"和"应用用哪个证书库"**。同一个根证书，系统信任了，Firefox / Steam 不一定信任。
2. **Firefox 用独立的 NSS 库**（`cert9.db`），系统 CA 与它无关；HSTS 站点没有"添加例外"。
3. **Steam 的内置浏览器 CEF 用 `~/.pki/nssdb`**，而且**新版 NSS 的 `certutil` 导入的条目，旧版 CEF 可能读不了**。用 NSS 3.98 的 `certutil` 重新导入可以修复。
4. **AppImage 与 deb 同版本也可能表现完全不同**。DSH 的 AppImage 换 deb 后渲染问题明显减少，先把"包"换掉，再调参数。
5. **"按钮能点、画面不动"不要默认是 GPU 画不出来**。这次软件渲染（llvmpipe + Skia CPU）仍然复现，说明问题在呈现/帧同步层，不是单纯光栅化。
6. **改启动器/环境变量后，一定用 `/proc/<pid>/environ` 验证真的生效**。本次多次出现"以为加了参数，实际启动路径没带上"的情况。
7. **清理时注意 `~/.local/bin` 的同名 wrapper 会遮蔽 `/usr/bin` 的可执行文件**，`command -v` 必须确认。
8. **全局 CSS / 主题补丁只能作为临时验证**，必须备份、可还原；应用更新会覆盖。
9. **桌面图标不显示，不一定是图标文件损坏**。GNOME Shell 会按应用/图标名缓存纹理；换一个**新的图标名 + 用户级 desktop 覆盖**，往往比反复覆盖同名文件更快生效。
10. **文件系统问题先分清"驱动"和"参数"**：这次符号链接失败的根因是内核 `ntfs3` 在**并发**下建链接失败，与 `acl`/`umask` 无关；换 `ntfs-3g`（FUSE）后 0 失败。
11. **单线程测试不能给并发问题下结论**。同一目录单线程 100 次全过、8 进程并发 320 次失败 192 次。
12. **系统级路径要"开机就存在"**：`/run/media/$USER/...` 是 tmpfs、登录后才有，重启后 Steam 库路径会直接消失；库路径要放 fstab 挂载的真实路径。
13. **Wayland 下外部进程无法最小化别人的窗口**，要做"窗口收纳"只能写 GNOME Shell 扩展；且原生 Wayland 窗口的 `app_id` 晚于 `window-created` 提交，匹配要靠 pid 兜底。
14. **root 权限按次授权**：`pkexec 命令` 每次弹密码框；多步操作写成一个脚本 `pkexec bash 脚本` 一次授权。NOPASSWD 只放行最小命令集。

## 环境

| 项 | 值 |
| - | - |
| 系统 | Ubuntu 26.04.1 LTS，kernel 7.0.0-38-generic |
| 桌面 | GNOME Shell 50.1，Wayland 会话 |
| GPU | NVIDIA GTX 1060 Mobile，驱动 580.178.04；Intel HD 630 核显 |
| WebKitGTK | 2.52.6-0ubuntu0.26.04.1 |
| 加速工具 | Steamcommunity_302 15.0.9（AppImage，HTTP/HTTPS 中间人 + hosts 重定向） |
| 浏览器 | Firefox 154（snap） |
| DSH | 桌面端 0.25.0；Harness 内核 0.2.1-rc.2 |
| 其它 | Steam 1.0.0.85、LX Music 2.12.6、QQ 3.2.32、微信 4.1.13.26 |
| 游戏库 | 外部 SATA SSD `/dev/sda2`（NTFS，931 G），挂 `/mnt/G1`（`ntfs-3g`，fstab 开机挂载） |
| 双系统 | 内部 NVMe `/dev/nvme0n1p3`（Windows，163.6 G）｜ `p4`（Ubuntu，74.5 G）；Windows 分区当前以**只读**挂到 `/mnt/win` |

> 注意：下文很多问题都来自 **Steamcommunity_302（S302）**。它把 `github.com`、`store.steampowered.com` 等域名写进 `/etc/hosts` 指向 `127.0.0.1`，并在本机 443 端口用自签根证书做 TLS 中间人。系统证书库信任它，不代表每个应用都信任。

## 脚本一览

| 脚本 | 用途 |
| - | - |
| [fix-firefox-s302-ca.sh](scripts/fix-firefox-s302-ca.sh) | 把 S302 根证书导入 Firefox 的 NSS 库（自动找 snap/deb 配置目录） |
| [fix-steam-s302-ca.sh](scripts/fix-steam-s302-ca.sh) | 用 NSS 3.98 的 `certutil` 重新导入 Steam 的 `~/.pki/nssdb` |
| [fix-dsh-icon.sh](scripts/fix-dsh-icon.sh) | 为 DSH 生成新名字的用户图标 + 用户级 desktop 覆盖，修空白图标 |
| [restart-dsh.sh](scripts/restart-dsh.sh) | 完全退出并重启 DSH 桌面端 |
| [set-scale.py](scripts/set-scale.py) | 调整显示缩放（1.0 / 1.25 / 1.5） |
| [install-quiet-startup.sh](scripts/install-quiet-startup.sh) | 安装 `quiet-startup@local` 扩展 + 3 个 autostart 入口（QQ/微信/DSH 安静自启） |
| [switch-g1-to-ntfs3g.sh](scripts/switch-g1-to-ntfs3g.sh) | 把 NTFS 游戏盘从 `ntfs3` 换成 `ntfs-3g`，并让「文件」侧栏可见（**当前采用**） |
| [fix-steam-ntfs-library.sh](scripts/fix-steam-ntfs-library.sh) | 对齐 Steam 库路径到开机挂载点、清掉重复挂载 |
| [proton-tools-on-ext4.sh](scripts/proton-tools-on-ext4.sh) | 备选：只把 Proton/Runtime + 前缀放内部 ext4（占 2.4 G），可 `--revert` |
| [move-proton-app-to-ext4.sh](scripts/move-proton-app-to-ext4.sh) | 备选：把某个 Proton 游戏整体搬到内部 ext4 库 |
| [revert-ext4-migration.sh](scripts/revert-ext4-migration.sh) | 撤销整库迁移，把游戏与工具搬回 NTFS |

扩展源码在 [gnome-extension/](gnome-extension/)（`quiet-startup@local`），DSH 档案快照在 [dsh/profile-config/](dsh/profile-config/)。

## 目录结构

```
.
├── README.md                 # 本索引
├── docs/                     # 按问题分类的详细记录
│   ├── lessons.md            # 经验总结（方法 / 教训 / 我犯过的错）
│   ├── 01-firefox-github-cert.md
│   ├── 02-install-qq-wechat-steam.md
│   ├── 03-steam-cert-error-202.md
│   ├── 04-lx-music.md
│   ├── 05-dsh-render-freeze.md
│   ├── 06-dsh-dock-icon-blank.md
│   ├── 07-dsh-deb-switch.md
│   ├── 08-dsh-feature-check.md
│   ├── 09-steam-proton-ntfs.md
│   ├── 10-quiet-autostart.md
│   ├── 11-rime-ime.md
│   ├── 12-variety-wallpaper.md
│   ├── 13-daily-tips.md
│   ├── 14-appendix-commands.md
│   ├── 15-unresolved.md
│   ├── 16-windows-dirty-volume.md
│   └── dsh-profile-tuning.md
├── scripts/                  # 幂等修复脚本（都先备份再改）
├── gnome-extension/          # 本地 GNOME Shell 扩展源码
├── dsh/profile-config/       # DSH 档案配置快照
└── assets/                   # 文档配图
```

## 免责声明

本文记录的是本机排障过程，命令具有破坏性（改证书库、hosts、系统参数）。复现前请备份，并确认你信任本机的中间人工具。音源/第三方插件涉及版权与安全风险，请自行判断。
