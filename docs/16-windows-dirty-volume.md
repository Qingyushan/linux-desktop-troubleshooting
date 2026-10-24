# Windows 分区（「176 GB 卷」）在文件管理器里挂载失败

> 返回索引：[README](../README.md) ｜ 相关脚本：无（fstab 一次性改动）

## 症状

GNOME「文件」侧栏点「176 GB 卷」，弹窗：

```
无法访问"176 GB 卷"
Error mounting /dev/nvme0n1p3 at /run/media/qys/E8186B3A186B06C2:
wrong fs type, bad option, bad superblock on /dev/nvme0n1p3,
missing codepage or helper program, or other error
```

顺带一提：这块盘是**内部 NVMe 的 Windows 系统分区**（163.6 G），和 Ubuntu 的 `/dev/nvme0n1p4` 是同一块盘上的双系统。

## 怎么定位

先看内核怎么说，一条命令定性：

```bash
journalctl -k -b | grep -i nvme0n1p3
```

```
ntfs3(nvme0n1p3): It is recommended to use chkdsk.
ntfs3(nvme0n1p3): volume is dirty and "force" flag is not set!
```

再用 `ntfsinfo` 看卷标记（需要 root）：

```bash
sudo ntfsinfo -m /dev/nvme0n1p3 | grep -i -E "volume|dirty|hibern"
```

```
Volume is scheduled for check.
```

## 根因

**不是驱动坏了，也不是分区表坏了**，而是 Windows 上次没有正常关机：快速启动（Fast Startup）本质是"混合休眠"，或者非正常断电，都会在 NTFS 卷上留下 **dirty 标记 / chkdsk 待检标记**。

于是：

- 内核 `ntfs3`：拒绝读写挂载（`volume is dirty and "force" flag is not set`）；
- `ntfs-3g`（FUSE）：同样拒绝读写挂载，只允许**只读**；
- udisks 默认按**读写**去挂 → 失败 → 文件管理器报上面那个错。

**强行 `force` 读写挂载是有风险的**：卷上可能有未落盘的元数据，边写边修容易把 Windows 的文件系统弄坏。

## 本次怎么解决的

1. **立即能用**：只读挂载（安全，不改动 Windows 分区的任何字节）：

   ```bash
   sudo mkdir -p /mnt/win
   sudo mount -t ntfs-3g -o ro,uid=1000,gid=1000,umask=022,iocharset=utf8 /dev/nvme0n1p3 /mnt/win
   ```

2. **持久化 + 侧栏可点**：写进 fstab，只读、开机挂载、并让「文件」侧栏显示为「Windows」：

   ```
   # Windows 系统分区（只读；卷带 chkdsk 标记，不可安全写入）
   UUID=E8186B3A186B06C2   /mnt/win   ntfs-3g   ro,nofail,uid=1000,gid=1000,umask=022,iocharset=utf8,x-gvfs-show,x-gvfs-name=Windows,x-systemd.device-timeout=10   0   0
   ```

   验证：

   ```bash
   findmnt /mnt/win            # fuseblk ro
   gio mount -l | grep -i windows
   #   Volume(0): Windows -> file:///mnt/win
   ls /mnt/win                 # Windows 的文件正常列出
   ```

现在侧栏里叫「Windows」，点进去就是只读浏览；`nofail` 保证盘有问题时不会卡住开机。

## 想恢复读写，三条路

| 做法 | 说明 | 风险 |
| --- | --- | --- |
| **进 Windows → 关闭快速启动 → 完整关机**（控制面板 → 电源选项 → 选择电源按钮的功能 → 取消"启用快速启动"） | 根治；之后 Linux 里可以直接读写挂载 | 最低，推荐 |
| **进 Windows 跑 `chkdsk C: /f`** | 让 Windows 自己把卷修干净 | 最低，推荐 |
| Linux 里 `sudo ntfsfix -d /dev/nvme0n1p3` | 只清 dirty 位（不是真正的 chkdsk） | 对 Windows 系统盘有风险；Windows 下次启动可能仍会自检 |

修好之后，把 fstab 那行的 `ro` 去掉，再 `sudo mount -o remount,rw /mnt/win`（或重启）即可读写。

## 经验

- **"文件管理器挂不上盘"先看内核日志**：`wrong fs type / bad superblock` 这类通用报错几乎没有信息量，`ntfs3` / `ntfs-3g` 自己的提示（dirty / chkdsk）才是真相。
- **Windows 双系统机器上，NTFS 分区被"弄脏"是常态**：快速启动不关，Linux 侧就永远只能只读。
- 只读挂载足以应付"我要从 Windows 分区拷个文件出来"，不要为了能写就 `force`。
