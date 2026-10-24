# Steam 商店 `Invalid SSL Certificate (error:-202 status:4)`

> 返回索引：[README](../README.md) ｜ 原始位置：§3 ｜ 相关脚本：`../scripts/fix-steam-s302-ca.sh`


### 现象

Steam 客户端商店页显示：

```
Invalid SSL Certificate
The SSL certificate for https://store.steampowered.com/ is invalid ...
(error:-202 status:4)
```

系统 `curl` 访问同一地址返回 200，证书链校验通过。Firefox 也能正常打开。

### 根因

Steam 的 CEF（steamwebhelper）使用 **`~/.pki/nssdb`**，不是系统证书库。S302 已把根证书写进该库，但它是用 **NSS 3.120 的 certutil** 导入的。社区已知：新版 certutil 写出的条目，Steam 的旧版 CEF 读不了，表现为 `net_error -202`。

验证：

```bash
certutil -L -d sql:$HOME/.pki/nssdb          # 条目的确在，trust C,,
lsof -p <steamwebhelper_pid> | grep nssdb    # Steam 的确打开了 cert9.db
```

### 修复

用一个**旧版 NSS（3.98）**的 `certutil` 重新导入。不要降级系统 NSS，单独解包旧工具即可：

```bash
# 1. 下载 Ubuntu 24.04 的 NSS 工具（noble，3.98）
base=http://cn.archive.ubuntu.com/ubuntu
mkdir -p /tmp/nssold
for p in \
  pool/main/n/nss/libnss3_3.98-1build1_amd64.deb \
  pool/main/n/nss/libnss3-tools_3.98-1build1_amd64.deb \
  pool/main/n/nspr/libnspr4_4.35-1.1build1_amd64.deb; do
  f=$(basename "$p")
  curl -sSL -o "/tmp/$f" "$base/$p"
  dpkg-deb -x "/tmp/$f" /tmp/nssold
done

OLD="env LD_LIBRARY_PATH=/tmp/nssold/usr/lib/x86_64-linux-gnu /tmp/nssold/usr/bin/certutil"

# 2. 关掉 Steam，备份 NSS 库
/usr/games/steam -shutdown
cp -a ~/.pki/nssdb ~/.pki/nssdb.bak-$(date +%Y%m%d-%H%M%S)

# 3. 删除旧条目，用旧 certutil 重新导入
CA=$(ls /usr/local/share/ca-certificates/s302-*-root-ca-*.crt | head -1)
$OLD -D -d sql:$HOME/.pki/nssdb -n "S302 V15 Root CA d942d737f8373d1c" 2>/dev/null || true
$OLD -A -d sql:$HOME/.pki/nssdb -n "Steamcommunity302 Root" -t "C,," -i "$CA"

# 4. 用新 certutil 也要能读
certutil -L -d sql:$HOME/.pki/nssdb | grep -i steam
```

> 旧工具目录里同时带 `libnss3.so`、`libnspr4.so`，靠 `LD_LIBRARY_PATH` 隔离，不影响系统 NSS。

### 附：界面改中文

Steam 关闭时编辑 `~/.steam/registry.vdf`，把 `HKCU\Software\Valve\Steam\language` 和 `Steamsteamglobal\language` 改成 `schinese`，重启后 `steamwebhelper` 会带 `-lang=zh_CN`。也可以在 **设置 → 界面** 里改。

### 经验

- 先确认“证书链对不对”和“应用用哪个库”，再谈信任。
- `certutil` 不是“只要导入就行”，**版本兼容性真实存在**。
- 修改 Steam NSS 库前备份；Steam 更新/重装 S302 后可能复发，保留一键修复脚本。

---
