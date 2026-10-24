# Steam / Proton 在 NTFS 库上的「兼容性工具失败」与启动即退

> 返回索引：[README](../README.md) ｜ 原始位置：§12.4（含 12.4.1~12.4.4） ｜ 相关脚本：`../scripts/switch-g1-to-ntfs3g.sh`、`../scripts/fix-steam-ntfs-library.sh`、`../scripts/proton-tools-on-ext4.sh`、`../scripts/move-proton-app-to-ext4.sh`


- S302 不在运行时，`/etc/hosts` 里指向 `127.0.0.1` 的域名会“连接被拒绝”；先启动 S302，再开 Steam / 浏览器。
- Steam 商店证书报 `-202` 时，跑仓库里的 `scripts/fix-steam-s302-ca.sh`；Firefox 报 `SEC_ERROR_UNKNOWN_ISSUER` 时跑 `scripts/fix-firefox-s302-ca.sh`。
- Steam 更新 / 重装后证书可能复发，脚本可以重复跑；跑之前会备份 NSS 库。
- 界面语言：Steam 设置 → 界面 → 简体中文；或者关闭 Steam 后改 `~/.steam/registry.vdf` 的 `language` 为 `schinese`。

### 启动游戏报「兼容性工具失败」

现象：点「开始游戏」立刻弹窗 `启动此游戏时发生错误：兼容性工具失败`，游戏根本没起来（本次是《米塔 MiSide》，Windows 游戏，走 Proton Experimental）。

**日志先看 `compat_log.txt`**，一行就能定性：

```bash
grep -nE "unsupported version|Loaded manifest|StartSession" ~/.steam/steam/logs/compat_log.txt | tail
```

本次的关键行：

```
[12:35:22] Registering tool proton_experimental, AppID 1493710
[12:35:22] Registering tool steamlinuxruntime_4, AppID 4183110
   # ← 注意：这次启动没有 "Loaded manifest for tool ..." 行
[12:37:57] Tool 1493710 "Proton Experimental" unsupported version 0.
```

**根因**：不是游戏坏了，也不是 Proton 文件坏了 —— 是 Steam 这次启动时**没读到** Proton / Steam Linux Runtime 的 `toolmanifest.vdf`，于是把这些兼容性工具登记成 `version 0`，之后任何启动请求都被拒。重启 Steam 后同一批工具正常打印 `Loaded manifest for tool 1493710.`，错误消失，游戏能进。

**修复（一条重启就够）**：

```bash
~/.steam/debian-installation/steam.sh -shutdown
nohup setsid ~/.steam/debian-installation/steam.sh >/dev/null 2>&1 &
# 40 秒后确认工具清单读到了：
grep "Loaded manifest for tool 1493710" ~/.steam/steam/logs/compat_log.txt | tail -1
```

**为什么读不到 / 怎么防复发**：本机 Steam 库在 NTFS 盘（`/dev/sda2`，ntfs3）上，Proton 和 Steam Linux Runtime 也躺在这块盘里。同一块盘当时还被 `fstab`（`/mnt/G1`）和 `udisks`（`/run/media/qys/G1`）**各挂了一份**，Steam 用的是 `/run/media/...` 这条随时可能消失的路径。做法：

```bash
./scripts/fix-steam-ntfs-library.sh --dry-run   # 先看会改什么
./scripts/fix-steam-ntfs-library.sh             # 对齐库路径到 /mnt/G1，卸掉重复挂载，重启 Steam
```

> 会关掉 Steam（游戏会退出），跑之前先存档。

**顺手能做的自检**：

```bash
# 容器本身是否健康（只跑 /usr/bin/true，不动游戏）
"/run/media/qys/G1/SteamLibrary/steamapps/common/SteamLinuxRuntime_4/_v2-entry-point" \
  --verb=run -- /usr/bin/true && echo "SLR4 OK"
# Proton 官方的说法：工具"损坏或不完整"时先验证完整性，并避开非 Linux 原生文件系统
# https://github.com/ValveSoftware/steam-for-linux/issues/12655
```

### NTFS 内核驱动（ntfs3）并发建符号链接会失败 → 改用 ntfs-3g

修好「兼容性工具失败」后，游戏能拉起 Proton 容器，但经常 2 秒就退出：

```
pressure-vessel-wrap: E: Unable to create symlink "./etc/ssl/certs/xxx.pem"
in "/mnt/G1/.../SteamLinuxRuntime_4/var/tmp-XXXX/usr": No such file or directory
```

**真正的根因是"并发"，不是"挂载选项"。** 同一挂载点、同一目录的两组测试：

| 测试方式 | 结果 |
| --- | --- |
| 单线程连续 100 次 `ln -s` | **0 失败** |
| 8 进程并发 × 40 次 = 320 次 | **192 失败** |
| 改成 ntfs-3g（FUSE）后同样 8×40 | **0 失败** |

pressure-vessel 建容器时就是**多线程并发**创建 `usr/etc/ssl/certs/*` 的符号链接，所以表现为"有时能进游戏、有时 2 秒退出"——取决于那一刻并发撞没撞上。挂载参数（`acl` / `umask` / `dmask` / `fmask`）与此无关，之前那些试错全都测错了方向。

**修复：把这块盘改用 FUSE 的 `ntfs-3g` 驱动**（仓库脚本，需要 root）：

```bash
sudo bash ./scripts/switch-g1-to-ntfs3g.sh
```

脚本做的事：关 Steam → 卸载 → 改 fstab（`ntfs3` → `ntfs-3g`，去掉 `prealloc`）→ 重挂 → 以普通用户身份做并发符号链接 + 冒号文件名验证。

fstab 最终形态：

```
UUID=26D4A177D4A14A3F   /mnt/G1   ntfs-3g   defaults,nofail,uid=1000,gid=1000,umask=022,iocharset=utf8,x-gvfs-show,x-gvfs-name=G1,x-systemd.device-timeout=10   0   0
```

实测结果：

- 并发符号链接 **0/320 失败**；Wine 需要的 `dosdevices/c:` 也能建；
- 读速基本无损：同一大文件 `dd` 直读 ntfs3 509 MB/s vs ntfs-3g 505 MB/s；
- MiSide 全链路（游戏本体 + Proton Experimental + Steam Linux Runtime + Wine 前缀）**全部留在 NTFS**，内部盘一点不占；
- 游戏正常启动（`App Running` 不回滚、窗口 3072×1728、CPU ~56%）。

**两个必须记住的坑**：

1. **不要给 ntfs-3g 加 `windows_names`**。它禁止文件名含 `:` `*` `?` `<` `>` `|` `"`，而 Wine 必须创建
   `dosdevices/c: -> ../drive_c`，加了就会报 `OSError: [Errno 22] Invalid argument`，前缀建到一半就挂。
2. **fstab 挂载的卷默认不出现在 GNOME「文件」侧栏**，要加 `x-gvfs-show`（配 `x-gvfs-name=G1` 起名）。
   本次顺手修好了：侧栏现在能看到「G1」，点进去就是 `/mnt/G1`。

### 备选方案（内部盘不紧张时）

如果不想动 fstab 的驱动，也可以只把 Proton 工具和前缀挪到内部 ext4、游戏本体留 NTFS（占 2.4 G）：

```bash
./scripts/proton-tools-on-ext4.sh            # 迁移
./scripts/proton-tools-on-ext4.sh --revert   # 回滚
```

它用启动项 `STEAM_COMPAT_DATA_PATH=<内部盘>/compatdata/<appid> %command%` 把前缀指过去。这条路验证过可用（MiSide 稳定运行），只是会占用内部盘，本次已回滚、不再使用。

### 长期建议

- 放 Steam 库**必须选 `ntfs-3g` 驱动**：内核 `ntfs3` 在本机并发建符号链接会成片失败（实测 192/320）；Valve 官方也只支持 Linux 原生文件系统（[steam-for-linux#12655](https://github.com/ValveSoftware/steam-for-linux/issues/12655)）。
- NTFS 用来放**数据**没问题，但 Proton 游戏还牵扯"工具清单读取、符号链接、可执行权限"，坑比普通数据盘多。
- 真正最省心的是把库放 ext4；但 800+ GB 的库搬迁成本高，目前这套（`ntfs-3g` + 游戏/工具/前缀全在 NTFS）已经能稳定跑，代价见文档开头的清单。
