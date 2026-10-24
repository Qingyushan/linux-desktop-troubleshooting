# Firefox 打开 GitHub 报 `SEC_ERROR_UNKNOWN_ISSUER`

> 返回索引：[README](../README.md) ｜ 原始位置：§1 ｜ 相关脚本：`../scripts/fix-firefox-s302-ca.sh`


### 现象

- 仅 GitHub 打不开，其它站点正常；
- 页面提示证书颁发者未知，HSTS 站点无法添加例外；
- 系统时间正确，GitHub 本身没有故障。

### 根因

S302 把 `github.com` 指向 `127.0.0.1:443`，用自签根证书重签证书。该根证书已装进**系统**证书库（`/usr/local/share/ca-certificates/s302-*.crt`），但 Firefox 使用**自己的 NSS 库**（snap 版在 `~/snap/firefox/common/.mozilla/firefox/<profile>/cert9.db`），看不到系统证书。

### 修复

```bash
# 1. 找到 Firefox 配置目录（snap 与 deb 路径不同）
ls -d ~/snap/firefox/common/.mozilla/firefox/*/ 2>/dev/null
ls -d ~/.mozilla/firefox/*/ 2>/dev/null

P="$HOME/snap/firefox/common/.mozilla/firefox/<profile>"
CA=$(ls /usr/local/share/ca-certificates/s302-*-root-ca-*.crt | head -1)

# 2. 备份并导入
cp -a "$P/cert9.db" "$P/cert9.db.bak-$(date +%Y%m%d-%H%M%S)"
certutil -A -n "Steamcommunity302 Root" -t "C,," -i "$CA" -d sql:"$P"

# 3. 确认
certutil -L -d sql:"$P" | grep -i steam
```

**必须完全退出 Firefox 再启动**（NSS 库只在启动时加载）。如果 DSH/聊天页面在 Firefox 里，重启会中断，重新打开即可。

### 经验

- 不要用“关闭 HSTS”或 `security.enterprise_roots.enabled` 这类偏方；直接导入根证书最干净。
- 导入的是**根证书**，不是服务器叶子证书。
- 这种根证书具备解密 HTTPS 的能力，只应装在本机、只应信任可信工具；不要把该 CA 扩散到其它设备。

---
