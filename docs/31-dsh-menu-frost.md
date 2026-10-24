# DSH 菜单毛玻璃：透明从哪来、怎么改、升级后怎么重放

> 返回索引：[README](../README.md) ｜ 相关：[29-dsh-web-headless.md](29-dsh-web-headless.md)（DSH Web 入口）、[26-fonts.md](26-fonts.md)

## 症状

DSH 桌面客户端（Tauri/WebKit，`dsh-tauri 0.25.0`）与 Firefox 里的 DSH 网页端，**设置菜单、后台任务浮层、旁问专家卡片半透明**：背后聊天文字清晰透出来，两行字叠在一起影响可读性。

容易误判成“窗口整体不透明度”问题，但实际原因是**两层**：

| 层 | 控制点 | 现象 |
| --- | --- | --- |
| 窗口整体不透明度 | `~/.local/share/dsh-tauri/.store.dat` 的 `setting.appearance.opacity`（默认 80） | 整个窗口透过壁纸/桌面 |
| 菜单/浮层材质 | 主题在 `<body>` 运行时注入的 `--dsw-menu-surface-fill`（深色 `#43454a73` = 45%，浅色 `#f8f9fa94` = 58%）+ `backdrop-filter: blur(40px) saturate(150%)` | 菜单透出背后文字 |

## 怎么定位

### 1. 先分清是哪一层

浏览器里（Firefox 打开 `http://127.0.0.1:3080`）也透 → 与窗口 opacity 无关，是网页 CSS。

### 2. 用无头浏览器读“真实生效值”

不靠猜，直接点开菜单读计算样式（Chrome 已装即可，不需要 GUI）：

```bash
google-chrome-stable --headless=new --no-sandbox \
  --user-data-dir=/tmp/dsh-probe --remote-debugging-port=9335 \
  --window-size=1400,900 http://127.0.0.1:3080 &
```

然后用 CDP（Node 22 自带 WebSocket）连 `http://127.0.0.1:9335/json/list`，执行：

```js
// 1) 找到左下角用户名并点击，弹出菜单
const el = [...document.querySelectorAll('*')]
  .find(e => e.children.length === 0 && e.textContent.trim() === '青雨杉');
const btn = el.closest('[role=button],button,[tabindex]') || el.parentElement;
btn.click(); btn.dispatchEvent(new MouseEvent('mousedown', {bubbles:true}));
btn.dispatchEvent(new MouseEvent('mouseup',   {bubbles:true}));

// 2) 读取菜单材质的计算样式
const m = document.querySelector('._material_ri079_21');
const cs = getComputedStyle(m);
cs.backgroundColor;   // rgba(248, 249, 250, 0.58)  ← 半透明来源
cs.backdropFilter;    // blur(40px) saturate(1.5)
```

期望：能抓到 **唯一一个** 半透明元素 `DIV._material_ri079_21`——菜单背景全部由它绘制。

### 3. 确认 token 是运行时注入的

```bash
grep -o "\-\-dsw-menu-surface-fill:[^;} ]*" \
  ~/.local/share/dsh-tauri/dependencies/dsh/node_modules/@deepseek-ai/dsh-client-ui-theme/lib/client.js
# --dsw-menu-surface-fill:#f8f9fa94   （浅色）
# --dsw-menu-surface-fill:#43454a73   （深色）
```

这些变量**不在 CSS 文件里**，是主题插件运行时 `<style>` 注入到 `<body>` 上的。

## 无效尝试（按翻车顺序）

| 尝试 | 结果/为什么无效 |
| --- | --- |
| 把 `.store.dat` 的 `appearance.opacity` 改成 100 | 客户端**退出时会把内存值写回**该文件，重启后又变回 80；且它只影响窗口整体，不影响菜单材质 |
| 只把 `--dsw-menu-backdrop-filter` 设成 `none`（去掉模糊） | **更糟**：底色仍是 45% 透明，失去模糊后背后文字清晰透出，比原来更不可读 |
| 在 CSS 末尾写 `:root{--dsw-menu-surface-fill:#43454a}`（无 `!important`） | 无效：该 token 定义在 `<body>`（运行时注入、更靠近元素），`:root` 的声明被覆盖 |
| 关掉壁纸引擎的玻璃（`glassWindow=false`） | 无关：菜单材质与壁纸引擎的 glass 是两套东西（实验后已恢复原设置） |
| 给 `[data-ds-dark-theme]` 写变量（无 `!important`） | 无效：同理被运行时注入的 body 级声明压过 |

## 最终方案

### 1. 窗口不透明度：启动前预写（绕开“退出时写回”）

`~/.local/bin/dsh-client`：

```bash
"$HOME/.local/bin/dsh-set-appearance" --blur off --opacity 100 >/dev/null 2>&1 || true
exec /usr/bin/deepseek-harness-desktop "$@"
```

并把 `~/.config/autostart/deepseek-harness-desktop.desktop` 的 `Exec=` 指到该包装器；`dsh-appearance.service` 也带同样参数兜底。这样每次启动前都写一次，退出写回 80 也不影响下次。

### 2. 菜单材质：直接覆盖材质层（保留毛玻璃）

`scripts/dsh-menu-frost.sh` 会找到当前构建产物（含版本化副本）里的材质类名，追加并用 `!important` 锁定：

```css
._material_ri079_21{
  background-color: rgba(248,249,250,0.65) !important;   /* 浅色 */
  backdrop-filter: blur(28px) saturate(150%) !important;
  -webkit-backdrop-filter: blur(28px) saturate(150%) !important;
}
body[data-ds-dark-theme] ._material_ri079_21{
  background-color: rgba(67,69,74,0.65) !important;      /* 深色 */
}
```

为什么是 82% + 36px：原版 45% + 40px 在模糊生效时好看，一旦模糊失效就退化成全透；82% 保证即便 `backdrop-filter` 不被支持（WebKitGTK 版本差异）也不会透到叠字，28px 让磨砂更明显。想要更实可 `0.80 24`，更玻璃可 `0.50 32`。

### 3. 使用与调参

```bash
scripts/dsh-menu-frost.sh            # 默认 0.82 / 36px
scripts/dsh-menu-frost.sh 0.60 44    # 更透、模糊更强
scripts/dsh-menu-frost.sh --remove   # 恢复主题原样
```

期望输出（每个构建产物一行）：

```
  ✔ /home/qys/.local/share/dsh-tauri/dependencies/dsh/node_modules/@deepseek-ai/dsh-web-frontend/dist/assets/index-BxpfOGf3.css  (applied ._material_ri079_21)
```

生效：浏览器 `Ctrl+Shift+R` 硬刷新；客户端 `Ctrl+R` 或退出重开（客户端是 3080 宿主，会断开几秒）。

### 3.1 卡片/子智能体：另一个 token

> **踩过的坑**：曾用 `[class*="_panel"]` 通配给“所有浮层/卡片”加毛玻璃，
> 结果命中了主内容面板（`P3OORG_panel`，675×857），把页面右侧涂成一大块实色、
> 布局看起来像坏了。**不要用这种宽泛属性选择器**，要落到具体组件类名或用 token 控制。

菜单之外，聊天流里的「旁问专家 / 子智能体」卡片用的是 `--dsw-specific-menu`
（主题里 `#303136f0` = 94%，且没有 backdrop-filter）。它不在 `.material` 覆盖范围内，
94% 在客户端和网页端看起来仍然“透出下层文字”。脚本一并把它提成实色：

```css
body{--dsw-specific-menu:#f8f9fa !important}                     /* 浅色 */
body[data-ds-dark-theme]{--dsw-specific-menu:#303136 !important}  /* 深色 */
```

实测（客户端 + Firefox 网页端一致）：卡片不再透，菜单仍是 65% + 28px 毛玻璃。

### 4. 验证（两种主题都测）

无头 Chrome 里 `Emulation.setEmulatedMedia` 切 `prefers-color-scheme`，再点开菜单读计算样式，期望：

```
LIGHT: menu rgba(248,249,250,0.82) blur(36px) | panel rgba(248,249,250,0.80) blur(40px)
DARK : menu rgba(67,69,74,0.82)     blur(36px) | panel rgba(67,69,74,0.80)     blur(40px)
```

## 回滚

```bash
# 1) 菜单恢复主题原样
scripts/dsh-menu-frost.sh --remove

# 2) 窗口不透明度恢复默认 80%
~/.local/bin/dsh-set-appearance --opacity 80

# 3) 启动包装器恢复直启
#    把 dsh-client 改回 exec /usr/bin/deepseek-harness-desktop "$@"
#    并让 autostart 的 Exec= 指回 /usr/bin/deepseek-harness-desktop
```

## 经验

- **先分清“窗口不透明度”和“元素半透明”**。前者在 `.store.dat`，后者在主题 token；只改一个另一个不变。
- **客户端设置文件是“启动时读、退出时写”**：外部改文件后必须重启，且下次退出会写回旧值——所以要么改 UI，要么在**启动前**预写。
- **CSS 覆盖半透明组件，别只改变量**：变量可能被运行时 `<style>` 注入到更深节点，必须用 `!important` 直接锁死绘制背景的那个元素（本例 `._material_*`）。
- **别单独去掉 blur**：模糊去掉后，剩下的透明度会显得更糟；要做的是“提高底色不透明度 + 保留适度模糊”。
- 构建产物 `index-<hash>.css` 会随 DSH 升级变化（文件名、类名都可能变），所以覆盖要脚本化：**升级后重跑 `scripts/dsh-menu-frost.sh`**。
- 排查这类“看起来是透明”的问题，无头浏览器 + CDP 读 `getComputedStyle` 比截图猜快得多，也能证明改没改对。
