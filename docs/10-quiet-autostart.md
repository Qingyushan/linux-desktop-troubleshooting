# QQ / 微信 / DSH 开机「安静」自启（窗口最小化，托盘常驻）

> 返回索引：[README](../README.md) ｜ 原始位置：§12.3 ｜ 相关脚本：`../scripts/install-quiet-startup.sh`、`../gnome-extension/quiet-startup@local/`


目标：登录后三个应用自己起来，但**主窗口不弹出来抢焦点**，托盘里能看到图标，点一下就回来。

**难点**：QQ、微信 4.x、DSH 桌面端现在都是原生 Wayland 窗口；Wayland 没有"让外部进程最小化别人窗口"的接口（`xdotool` / `wmctrl` 只对 XWayland 窗口有效），所以没法靠"启动后再把窗口藏起来"的脚本。唯一能做这件事的是**跑在 GNOME Shell 进程里的扩展**。

**做法**：一个本地小扩展 `quiet-startup@local` + 三个 autostart 入口。

- 登录后 300 秒内，**每 500ms 扫描全部窗口**，命中名单就 `minimize()`；
- 命中判定有两条路（缺一不可，原因见下面的复盘）：
  1. 窗口名：`wm_class` / `app_id`，精确比对 + 长标识（≥4 字符）包含匹配；
  2. 进程兜底：`win.get_pid()` → 读 `/proc/<pid>/cmdline`，命中 `/opt/qq/qq`、`wechat`、`deepseek-harness-desktop`；
- 首次命中即使窗口带着焦点也压下去（登录时 autostart 窗口通常自带焦点）；
- **先判断"这是不是自启的进程"**：`autostartProcessGraceSeconds`（默认 120 秒）——进程比 GNOME Shell 晚启动超过 2 分钟，就当作用户自己打开的程序，**整个进程都不管**（QQ 登录时 2 秒内就起来了，而你手动开的是几分钟后，区分得很干净）；
- **只管启动阶段出现的窗口**：从扩展 enable 起 `startupPhaseSeconds`（默认 60 秒）内第一次看到的窗口才可能被压；之后出现的窗口（QQ 新建聊天窗）**一律不管**；
- **只在登录时启用才接管**：扩展如果是会话中途被启用/重载的（shell 已运行远超启动阶段），直接进入 inert，不动任何窗口——否则装个新版本插件的瞬间就会把你正在用的窗口收走；
- **短暂的"自动登录宽限"**：从该窗口第一次被压算起 `focusGraceSeconds`（默认 10 秒）内，即使窗口有焦点也继续压，用来覆盖 QQ / 微信自动登录完成后自己把面板顶回来的几下；
- **超出宽限后，窗口一拿到焦点就永久让位**（内部记 `yielded`），之后无论它怎么失焦、怎么切换都再也不碰它 —— 这样你正在用的时候不会被反复收回；
- 同一窗口两次压制至少间隔 `minRetryGapSeconds`（默认 2 秒），避免 500ms 的扫描节奏把应用连击；
- 每个窗口总共最多压 `maxRetries`（默认 5）次；
- 300 秒后彻底放手，之后手动开这些应用、开新的聊天窗口都不受影响。

安装（幂等，可重复执行）：

```bash
./scripts/install-quiet-startup.sh
```

| 路径 | 作用 |
| --- | --- |
| `~/.local/share/gnome-shell/extensions/quiet-startup@local/` | 扩展本体（源码在仓库 `gnome-extension/`） |
| `~/.config/quiet-startup/config.json` | 窗口期秒数、重试次数、窗口名列表 `apps`、进程兜底列表 `processes` |
| `~/.config/autostart/{wechat,qq,deepseek-harness-desktop}.desktop` | 自启入口，延迟 8 / 12 / 5 秒 |
| dconf `org.gnome.shell enabled-extensions` | 启用扩展（保留已有的其它扩展） |

**必须注销重登一次**：GNOME Shell 只在自己的启动流程里扫描扩展目录，运行期新加的扩展不会被发现（此时 `gnome-extensions enable` 会报"扩展不存在"，不是配置错了）。

重登后验证：

```bash
gnome-extensions info quiet-startup@local    # State 应为 ENABLED
cat /tmp/quiet-startup.log
```

正常的日志长这样（`app=` 是窗口名命中，`process=` 是 pid 兜底命中，两种都算成功）：

```
== enable: apps=deepseek-harness-desktop,qq,wechat,... procs=/opt/qq/qq,wechat,... window=150s
existing windows: pid=0 names=-
created: pid=4094 names=qq
minimize(created#1): app=qq pid=4094 names=qq
created: pid=4156 names=-
minimize(scan#1): process=wechat pid=4156 names=wechat
```

> 想验证"现在就行"而不重登，可以看 `existing windows:` 那一行：它会把当前所有窗口的 pid 和名字打出来。

托盘图标：QQ / DSH 走 SNI，由 Ubuntu 自带的 AppIndicator 扩展显示；微信 4.x 内置 SNI 支持，登录后出现在托盘（未登录时只有登录窗口，托盘还没建）。

名单不对（某个应用还是弹窗）时：看日志 `created:` 后面的名字，加进 `config.json` 的 `apps` 数组，再

```bash
gnome-extensions disable quiet-startup@local && gnome-extensions enable quiet-startup@local
```

（改配置不用重登，改 `extension.js` 代码才需要重登。）

取消：

```bash
gnome-extensions disable quiet-startup@local          # 只停"最小化"，自启保留
sed -i 's/^X-GNOME-Autostart-enabled=true/X-GNOME-Autostart-enabled=false/' \
    ~/.config/autostart/{wechat,qq,deepseek-harness-desktop}.desktop   # 连自启一起停
```

**复盘：第一版为什么没生效**

第一版只在 `window-created` 时按窗口名匹配一次，结果重启后 QQ 被最小化了、微信和 DSH 没有。日志说明了原因：

```
[12:01:59] created: qq
[12:01:59] minimize(created#1): app=qq names=qq        <- XWayland，创建时就有 WM_CLASS
[12:02:00] created: (no name)                          <- 原生 Wayland，创建时 app_id 还没提交
[12:02:00] created: (no name)
```

同一批窗口在几十毫秒后（重新 enable 时打印的 `existing windows:`）名字就变成了 `qq` / `wechat` / `deepseek-harness-desktop`。也就是说 **`app_id` 是在 `window-created` 之后才提交的**，一次性匹配必然漏掉原生 Wayland 窗口。所以改成"持续扫描 + 进程 pid 兜底"：即使 `app_id` 永远为空的窗口，也能靠 `/proc/<pid>/cmdline` 认出来。

**复盘二：QQ 自动登录后窗口又回来了**

第二版生效后（重启验证），QQ 的登录框确实被压下去了，但自动登录完成后主面板又冒出来。日志显示这是应用自己在抢，不是扩展没匹配上：

```
[12:54:19] minimize(created#1): app=qq pid=4236
[12:54:24] minimize(created#1): app=qq pid=4236     ← QQ 自己又顶了一个窗口
[12:54:47] minimize(scan#2):  app=qq pid=4236       ← 28 秒后被扫到又压回去
[12:55:40] minimize(scan#3):  app=qq pid=4236       ← 又顶，又压
[12:56:47] disarm: login window elapsed             ← 之后 QQ 再顶就没人管了
```

两个问题：① `maxRetries=3` 太少，QQ 顶的次数比这多；② 原来的「有焦点就让位」规则把"应用自己顶上来"误判成"用户手动还原"。改法就是上面的宽限期 + 提高重试次数 + 窗口期延长到 300 秒。

**复盘三：QQ 在使用中被反复收回（16:55 那次登录）**

把宽限期从"距上次压制"改成"从首次压制起算"之前，宽限是**滑动**的：每压一次就把宽限重置一次，于是扫描每 500ms 看到窗口又被应用顶回来就再压一次，日志里 5 秒内连压 6 次：

```
[16:55:40] minimize(scan#3): app=qq
[16:55:41] minimize(scan#4): app=qq
[16:55:43] minimize(scan#5): app=qq
[16:55:43] minimize(scan#6): app=qq
[16:55:44] minimize(scan#7): app=qq
[16:55:45] minimize(scan#8): app=qq
```

用户在用的是时候窗口就被这样反复收走。修法三条（见上）：宽限从"首次压制"起算且只有 10 秒、**宽限过后一有焦点就永久 `yielded`**、两次压制之间至少隔 2 秒。

> 顺带记一个常被误解的点：**autostart 入口不是常驻脚本**。`~/.config/autostart/*.desktop` 的 `Exec` 就是应用本身（如 `/opt/QQ/qq`），启动完就退出，没有后台进程；维持"登录后别弹窗"的是 GNOME Shell 扩展，它在 `loginWindowSeconds`（300 秒）后自己 disarm，日志里会打印 `disarm: login window elapsed`，之后完全不再扫描窗口。

**复盘四：重启后 QQ 仍被反复收回（17:18 那次开机）**

新逻辑（焦点=让位）确实生效了，日志里有 `yield:` 和 `disarm:`，但仍然出问题：

```
[17:23:41] created: pid=4253 names=qq
[17:23:41] minimize(created#1): app=qq     ← 用户自己开 QQ，被当成自启窗口
[17:23:46] minimize(scan#2): app=qq
[17:23:49] minimize(scan#3): app=qq
[17:23:52] yield: 窗口已由用户接管          ← 让位生效
[17:24:01] created: pid=4253 names=qq
[17:24:01] minimize(created#1): app=qq     ← 同进程新建窗口，又重新开始压
[17:24:01] disarm: login window elapsed
```

两个漏洞：

1. **"第一次看到就压"没有时间边界**：`loginWindowSeconds=300` 意味着登录后 5 分钟内，任何新出现的匹配窗口都会被当自启窗口压掉。用户 4 分半时自己开 QQ，立刻被收走。
2. **让位只按窗口记，不按进程记**：接管了窗口 A，QQ 又新建窗口 B，B 没有 yield 标记，于是从头再压一遍。

修法：
1. `startupPhaseSeconds`（默认 60 秒）：只接管启动阶段出现的窗口；
2. 让位按 pid 记（`_yieldedPids`），该程序之后新建的窗口一律不碰；
3. `autostartProcessGraceSeconds`（默认 120 秒）：进程比 shell 晚启动超过 2 分钟就整个不管——这是最本质的一条，QQ 登录时 2 秒内就启动，手动打开是几分钟后；
4. 中途启用（shell 已运行很久）直接 inert，避免"装版本→扩展重载→把当前窗口收走"。

> 另一个血泪点：**改完扩展文件不会立刻生效**，GNOME Shell 把 ESM 模块缓存在内存里（`gnome-extensions disable/enable` 也只是重跑旧模块）。判据：日志头里有没有新字段（如 `shellUptime=`）。没有就说明还在跑旧代码，必须注销重登。

**踩过的坑**：**踩过的坑**：

- 旧 AppImage 时代留下的 `~/.config/autostart/Deepseek Harness Desktop.desktop` 是重复入口，会让 DSH 被拉起两次（第二次激活还会把刚最小化的窗口顶回来）；已挪到 `~/.config/autostart-disabled/`。
- 别为了"藏窗口"去开 `force_xwayland=true` 或 `GDK_BACKEND=x11`：那等于把 DSH 整个会话换回 XWayland，可能把 [05-dsh-render-freeze.md](05-dsh-render-freeze.md) 里的"只有 resize 才刷新"重新引回来。
- 别用 `xdotool windowunmap` 硬藏窗口：应用会以为自己仍然可见，之后的焦点/输入行为会变得很怪；`minimize()` 才是正常路径。
- 微信/QQ 如果没有自动登录，第一次出现的**登录窗口也会被最小化**：点 Dock 图标或托盘菜单里的"显示主面板"即可。
- 自启入口里带 `X-GNOME-Autostart-Delay` 是为了错开登录瞬间的 IO；DSH 自己设置里的"开机自启"如果被重开，可能把 `Exec` 改回不带延迟的原始命令——窗口仍然会被扩展最小化，不影响结果。
- 改完 `extension.js` **必须重新登录**才生效：GNOME 45+ 用 ESM 加载扩展，`gnome-extensions disable/enable` 会复用模块缓存，改了代码也不会重新读（实测日志里还是旧格式）。改 `config.json` 则只需 disable/enable。
- autostart 应用的窗口在登录阶段本来就会带焦点，「有焦点就让位」不能当通用规则用；正确做法是"刚压过就无视焦点、隔久了才让位"（`focusGraceSeconds`）。
- "第一次看到就压"必须有时间边界，否则用户登录后几分钟内自己打开应用也会被压——见 `startupPhaseSeconds`。
- "让位"要按 **pid** 记，不能只按窗口记：应用新建窗口会重置一切，用户会感觉"又来了"。
- 但"刚压过就无视焦点"如果做成**滑动**宽限，就会变成 500ms 一次的连击。正确做法是：宽限只从首次压制起算，且宽限结束后**焦点 = 永久让位**，两次压制之间再加最小间隔。
- 别用"窗口有焦点就不压"当作首次命中的条件：autostart 的窗口本来就会拿焦点，加了这条等于一个都不压。正确做法是首次命中照压、只在"用户还原后"让位。

## 现状（2026-10-24 晚调整）

DSH 桌面客户端**是 3080 的宿主**（systemd 无头服务已停用，见 [17-dsh-web-headless.md](17-dsh-web-headless.md)），所以名单里**保留** DSH：

- `apps` 与 `processes` 都含 `deepseek-harness-desktop`，登录后它的窗口会被最小化到托盘；
- 新版扩展的闸门能区分“自启的 DSH”和“你手动开的”：进程比 shell 晚启动 >120 秒就整个 pid 不管，窗口只在 enable 后 60 秒内出现才压，你点中过就永久让位；
- 现在安静自启的是 **QQ + 微信 + DSH 客户端**三家。
