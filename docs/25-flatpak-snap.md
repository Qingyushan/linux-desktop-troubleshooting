# Snap / Flatpak 沙箱：应用读不到文件、打不开外置盘

> 返回索引：[README](../README.md) ｜ 相关：[17-g1-automount.md](17-g1-automount.md)（外置盘路径）、[20-wayland-screenshare.md](20-wayland-screenshare.md)（portal） ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 项 | 值 |
|---|---|
| Snap | `snapd 2.77.1+ubuntu26.04.2`，已装 `bare`、`core22`、`core24`、`firefox`、`thunderbird`、`snapd`、`desktop-security-center` 等 |
| Flatpak | **未安装** |
| Portal | `xdg-desktop-portal` 1.21.1 + `-gnome` 50.0 + `-gtk`（沙箱应用访问文件/屏幕的唯一通道） |

> 本机 Firefox / Thunderbird 是 **snap 版**，所以"应用读不到 `/mnt/G1`"这类问题迟早会遇到。

---

## 1. 沙箱不是 bug：应用默认只能看自己的家目录

Snap 应用默认映射：

- 可见：`~/`（snap 内的 `$HOME`）、`/tmp`（私有）；
- 不可见：`/mnt/*`、`/media/*`、`/run/media/*`、其他用户目录、`/usr` 的可写部分。

Flatpak 类似，默认只给 `~` 和少数 XDG 目录。

**所以症状很好认**：文件管理器里看得见 `/mnt/G1`，但 snap 版应用里看不到，或打开时报"没有权限"。

---

## 2. Snap：查接口、连接口

### 查当前权限

```bash
snap connections firefox
# 输出里能看到 interface、plug、slot，以及 manual/auto
snap connections | grep -E "removable-media|home|mount-observe"
```

### 关键接口

| 接口 | 作用 | 需要的场景 |
|---|---|---|
| `home` | 访问 `$HOME` | 默认已连 |
| **`removable-media`** | 访问 `/mnt`、`/media`、`/run/media` | 读写 G1（`/mnt/G1`） |
| `mount-observe` | 只读观察挂载表 | 应用要枚举磁盘 |
| `system-files` | 特定系统路径 | 少见，需 snap 声明 |

### 连接（不需要 root）

```bash
snap connect firefox:removable-media    # 若报告不存在，说明该 snap 没声明这个 plug
```

> snapd 2.77 起 `removable-media` 也支持 `:removable-media` 形式的用户级授权；老版本需要 `sudo snap connect`。

### 验证

```bash
snap run --shell firefox -c 'ls /mnt/G1 | head'
# 有输出 = 接口生效；Permission denied / No such file = 没连上
```

---

## 3. Flatpak（本机未装，装了之后这么查）

```bash
flatpak --version
flatpak list --app
flatpak info --show-permissions org.mozilla.firefox
# 期望能看到 filesystems=... 一行

# 授予访问 /mnt/G1：
flatpak override --user --filesystem=/mnt/G1 org.mozilla.firefox
# 或者给整个 removable：
flatpak override --user --filesystem=/mnt org.mozilla.firefox
```

---

## 4. portal：沙箱访问"外面"的正规通道

沙箱应用要打开任意文件、截图、共享屏幕，都必须走 **portal**：

```bash
systemctl --user status xdg-desktop-portal xdg-desktop-portal-gnome --no-pager | head
```

portal 挂了的现象：

- 文件选择框弹不出来（或弹出来是空白）；
- 屏幕共享黑屏（详见 [20](20-wayland-screenshare.md)）；
- Flatpak 应用报 `GDBus.Error: org.freedesktop.portal.Error.Failed`。

修复通常就是重启 portal：

```bash
systemctl --user restart xdg-desktop-portal-gnome && systemctl --user restart xdg-desktop-portal
```

---

## 5. 常见症状对照

| 症状 | 原因 | 处理 |
|---|---|---|
| snap 应用看不到 `/mnt/G1` | 没连 `removable-media` | `snap connect <app>:removable-media` |
| snap Firefox 下载到 `~/Downloads` 正常，另存到 G1 失败 | 同上 | 同上 |
| 应用提示"文件不存在"但路径确实在 | 沙箱路径映射（`/home/...` vs `/run/user/.../doc/...`） | 用 portal 文件选择器打开 |
| Flatpak 读不到外部盘 | 缺 `--filesystem` | `flatpak override --user --filesystem=/mnt/G1` |
| 文件选择框空白 | portal 异常 | 重启 portal |
| snap 应用主题/图标不对 | `gtk-common-themes` 未连 | `snap connect <app>:gtk-3-themes` |

---

## 6. 无效尝试

- **改文件权限 `chmod 777`**：沙箱是**路径不可见**，不是权限位问题，777 也没用。
- **用 `sudo` 启动 snap 应用**：snap 不支持 root 运行，会直接报错。
- **把文件复制到 `~` 里再用**：能用但很别扭，正确做法是连接口。
- **以为 `snap connect` 一定要 root**：普通用户对自己安装的 snap 可以连 `removable-media` 等接口，不需要 sudo。

---

## 7. 经验

1. **"看得见但打不开"先怀疑沙箱**，尤其 `/mnt`、`/media` 下的外置盘。
2. **`snap connections <app>` 一屏看清权限**，比翻文档快。
3. **portal 是沙箱的通用出口**，它挂了会同时表现为"文件打不开 + 屏幕共享黑屏"。
4. **G1 挂到 `/mnt/G1` 后，snap 应用额外需要 `removable-media`**——这是 [17](17-g1-automount.md) 之后紧接着会遇到的问题。
