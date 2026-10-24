# G1 盘开机自动挂载，以及 ntfs-3g 与 ntfs3 怎么选

> 返回索引：[README](../README.md) ｜ 相关：第 9 篇（Steam / Proton 在 NTFS 库上失败）、第 16 篇（Windows 分区只读挂载）

## 目标

G1 是一块 931.5 GB 的 SATA 盘（`/dev/sda2`，NTFS，UUID `26D4A177D4A14A3F`），里面放 Steam 库。默认行为是**登录后由 udisks 按需挂载**到 `/run/media/<user>/G1`——问题有三个：

- `/run` 是 tmpfs，路径只在当前会话存在；
- 挂载点是会话相关的，换用户就变；
- 想指定参数（uid、umask、显示名）时 udisks 不一定让你加。

所以改成 **fstab 开机挂载到 `/mnt/G1`**。

## 最终配置

`/etc/fstab`（第 15 行）：

```
# G1 (NTFS, 开机自动挂载) — added 2026-10-24
UUID=26D4A177D4A14A3F   /mnt/G1   ntfs-3g   defaults,nofail,uid=1000,gid=1000,umask=022,iocharset=utf8,x-gvfs-show,x-gvfs-name=G1,x-systemd.device-timeout=10   0   0
```

逐项说明：

| 参数 | 作用 |
|---|---|
| `nofail` | 盘不在（没插、坏了）时**不阻塞开机**，直接跳过 |
| `x-systemd.device-timeout=10` | 最多等设备 10 秒，避免卡在 emergency shell |
| `uid=1000,gid=1000` | 挂载后归当前用户所有（NTFS 没有 Unix 权限位，只能这样映射） |
| `umask=022` | 文件 644 / 目录 755：本人读写、其他用户只读 |
| `iocharset=utf8` | 中文文件名不乱码 |
| `x-gvfs-show` / `x-gvfs-name=G1` | 让「文件」侧栏直接显示这块盘，而不是只在 `/mnt` 里藏着 |

## 坑一：双挂载

改完 fstab 立刻 `mount /mnt/G1`，会出现**同一个设备挂在两个点**：

```
/dev/sda2 on /run/media/qys/G1 type ntfs3 (...)
/dev/sda2 on /mnt/G1        type ntfs3 (...)
```

原因：udisks 在你登录时已经挂了一份，fstab 又挂一份；Linux 允许同一块设备挂在多个挂载点。

- 它们共用同一个超级块（`stat -c %d` 两个路径都是同一个值），**不会**出现“一边写另一边看不到”的缓存分裂，但路径不唯一会让 Steam 库指向飘忽不定。
- 清理时如果 `umount` 报 `target is busy`，多半是文件管理器还开着那个目录：`fuser -vm /run/media/qys/G1` 能看到占用的进程，关掉窗口或 `nautilus -q` 再卸。
- 最省事的办法：**直接重启**。开机会按 fstab 挂 `/mnt/G1`，udisks 见设备已挂载就不会再挂一份。

本次验证（重启后）：

```bash
$ findmnt -rn -S /dev/sda2 -o TARGET,FSTYPE,OPTIONS
/mnt/G1 fuseblk rw,relatime,user_id=0,group_id=0,default_permissions,allow_other,...

$ ls -ld /mnt/G1
drwxr-xr-x+ 1 qys qys 8192 ... /mnt/G1        # 写入、删除实测通过

$ systemctl status mnt-G1.mount --no-pager | head -3
● mnt-G1.mount - /mnt/G1
     Active: active (mounted) since ...
```

## 坑二：ntfs3 还是 ntfs-3g

两者都能读写 NTFS，但实现位置不同：

| | ntfs3 | ntfs-3g |
|---|---|---|
| 实现 | 内核驱动（Linux 5.15+） | FUSE 用户态驱动 |
| 性能 | 更快（走 VFS，无 FUSE 开销） | 稍慢 |
| 稳定/兼容 | 较新，异常卸载、并发写、压缩/稀疏文件等边角情况出过问题 | 老牌实现，各类工具链（含 Wine/Proton）踩坑少 |
| 典型症状 | Steam/Proton 报「兼容性工具失败」、启动即退；`fuseblk` 特有的参数不接受 | 吞吐略低，CPU 占用略高 |

本机的取舍：**G1 用 ntfs-3g**。理由是这块盘主要给 Steam 用，Proton 对 NTFS 的调用路径（大量小文件、并发元数据操作）在 ntfs3 上出过「兼容性工具失败」；牺牲一点吞吐换稳定是划算的。Windows 系统分区则只读挂载，避免碰 chkdsk 标记（见第 16 篇）。

> 判断“实际生效的是哪个驱动”不要看 fstab 里写的类型，要看挂载结果：`findmnt -no FSTYPE /mnt/G1`，`ntfs3` 显示为 `ntfs3`，ntfs-3g 显示为 `fuseblk`。

## 验证清单

```bash
findmnt -rn -S /dev/sda2 -o TARGET,FSTYPE,OPTIONS   # 只应有一个挂载点
systemctl status mnt-G1.mount --no-pager | head -5  # 由 fstab 生成的 .mount 单元
touch /mnt/G1/.write-test && rm /mnt/G1/.write-test # 读写权限
ls /run/media/$USER/ 2>/dev/null                    # 应为空（没有重复挂载）
```

## 回滚

```bash
sudo cp /etc/fstab.bak-<时间戳> /etc/fstab   # 脚本写的备份
# 或者手动删掉 UUID=26D4A177D4A14A3F 那一行
sudo systemctl daemon-reload
sudo umount /mnt/G1
```

删掉 fstab 行后，插盘/登录又回到 udisks 的 `/run/media/<user>/G1` 行为。
