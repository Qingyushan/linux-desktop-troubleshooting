# Wi-Fi 连不上、能 ping IP 但打不开网页（DNS）

> 返回索引：[README](../README.md) ｜ 相关：[20-wayland-screenshare.md](20-wayland-screenshare.md) ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 项 | 值 |
|---|---|
| 接口 | `wlp3s0`（Wi-Fi，已连接）、`enp2s0`（有线，unavailable）、`p2p-dev-wlp3s0` |
| 管理 | NetworkManager（`nmcli`） |
| DNS | `systemd-resolved`，`/etc/resolv.conf` → `/run/systemd/resolve/stub-resolv.conf` |
| 当前 DNS | **10.15.3.223**（路由器下发），`DNSSEC=no/unsupported`，`DNSOverTLS=no` |

---

## 1. 先把"连不上"和"解析不了"分开

| 现象 | 说明 | 查哪 |
|---|---|---|
| `nmcli` 里 Wi-Fi 未连接 | 关联/认证失败 | 驱动、密码、频段、隐藏 SSID |
| 连上了，`ping 8.8.8.8` 通，`ping baidu.com` 不通 | **DNS** 问题 | resolved、上游 DNS |
| 连上了，`ping` 也超时 | 路由/网关/NAT | 网关、默认路由 |
| 只有某些网站打不开 | MTU / 代理 / 证书 | 单独看（证书见 [01](01-firefox-github-cert.md)） |

---

## 2. 三步定位

### 第 1 步：链路状态

```bash
nmcli device status
# 期望：wlp3s0  wifi  connected
nmcli -f GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS device show wlp3s0 | head
```

### 第 2 步：路由与网关

```bash
ip route | head -5
# 期望：default via <网关> dev wlp3s0
ping -c2 <网关IP>
```

### 第 3 步：DNS

```bash
resolvectl status | grep -E "Current DNS|DNS Servers|DNS Domain"
# 本机：Current DNS Server: 10.15.3.223

resolvectl query www.baidu.com     # 能看到解析过程和结果
dig +short www.baidu.com @10.15.3.223   # 直连 DNS 服务器测试
```

**判定**：`resolvectl query` 失败而 `dig @8.8.8.8` 成功 → 上游 DNS 有问题，换 DNS。

---

## 3. 改 DNS 的三种方式

### 方式 1：只改当前连接（推荐，可回滚）

```bash
nmcli connection modify "<连接名>" ipv4.dns "223.5.5.5 119.29.29.29"
nmcli connection modify "<连接名>" ipv4.ignore-auto-dns yes
nmcli connection up "<连接名>"
```

### 方式 2：全局（systemd-resolved）

```bash
sudo mkdir -p /etc/systemd/resolved.conf.d
printf '[Resolve]\nDNS=223.5.5.5 119.29.29.29\nFallbackDNS=8.8.8.8\n' | sudo tee /etc/systemd/resolved.conf.d/dns.conf
sudo systemctl restart systemd-resolved
```

### 方式 3：关掉 resolved 的 stub（不推荐）

`/etc/resolv.conf` 是软链是 init 的系统符号链接，别手动覆盖成静态文件——NetworkManager 和 resolved 会反复改回去，症状是"改了又变"。

---

## 4. Wi-Fi 特有的坑

| 症状 | 原因 | 处理 |
|---|---|---|
| 能看到网络但连不上 | 密码/加密方式（WPA3 vs WPA2） | `nmcli connection show <名>` 看 `802-11-wireless-security.key-mgmt` |
| 5GHz 连不上、2.4G 正常 | 卡片不支持该频段/信道 | `iw phy phy0 info \| grep -A3 "Frequencies:"` 看支持范围 |
| 隐藏 SSID 连不上 | 需要显式 `hidden yes` | `nmcli connection modify ... wifi.hidden yes` |
| 频繁掉线 | 省电模式/驱动 | `nmcli connection modify ... wifi.powersave 2`（2=关闭省电） |
| 有线插上却 unavailable | 网口被禁用/驱动 | `ip link set enp2s0 up`；`dmesg \| grep -i enp2s0` |

---

## 5. 无效尝试

- **手动改 `/etc/resolv.conf`**：会被 NetworkManager/resolved 覆盖，看起来"又变回去了"。
- **重装 NetworkManager**：绝大多数是配置/驱动问题。
- **同时开 NetworkManager 和 systemd-networkd**：两者抢接口，表现为时通时不通。`systemctl status systemd-networkd` 应该是 inactive。
- **删 `/etc/NetworkManager/system-connections/` 全部配置**：会丢所有 Wi-Fi 密码，先备份。

---

## 6. 速查

| 症状 | 先查 |
|---|---|
| 连不上 Wi-Fi | `nmcli device status`、`nmcli connection show` |
| 能 ping IP 不能解析 | `resolvectl query`、`resolvectl status` |
| 只有部分站点打不开 | MTU（`ip link show wlp3s0`）、代理、证书 |
| 频繁断连 | 省电、信道、驱动日志 `dmesg \| grep -i wlp3s0` |
| 改 DNS 又变回去 | 是否开了两个网络管理器 |

## 7. 经验

1. **先 ping IP 再 ping 域名**，一步区分网络层和 DNS 层。
2. **`resolvectl query` 比 `nslookup` 信息更全**，能看到走的是哪个服务器。
3. **别手改 `/etc/resolv.conf`**，改连接或 resolved 的 drop-in。
4. **`enp2s0 unavailable` 是本机常态**（没插网线），不代表网卡坏了。
