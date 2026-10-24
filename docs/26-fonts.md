# 中文字体：显示成日文字形、发虚、粗体缺失

> 返回索引：[README](../README.md) ｜ 相关：[13-daily-tips.md](13-daily-tips.md) ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 项 | 值 |
|---|---|
| 字体总数 | `fc-list \| wc -l` = **604** |
| 中文字体 | `fc-list :lang=zh \| wc -l` = **89** |
| **中文实际匹配** | `fc-match sans-serif:lang=zh` → **`NotoSansCJK-Regular.ttc: "Noto Sans CJK JP"`** |

最后一行是重点：**系统给中文挑的是日文字体（JP）**。这正是"中文看起来怪、某些字是日式写法"的根源。

---

## 1. 三种表现，根因不同

| 表现 | 原因 |
|---|---|
| 中文里部分字是**日式字形**（如「直」「骨」「次」的写法） | fontconfig 对 CJK 的族选择偏向 JP |
| 中文**发虚/糊** | 无 hinting、缩放非整数、次像素渲染被关 |
| **粗体缺失**（只有一种字重） | 只装了 Regular，没有 Bold；或字体族不匹配 |

---

## 2. 判断"到底用了哪个字体"

```bash
fc-match sans-serif:lang=zh          # 本机：Noto Sans CJK JP  ← 问题所在
fc-match serif:lang=zh
fc-match monospace:lang=zh

# 看某个中文字体是否装了 SC 版本
fc-list | grep -i "CJK SC" | head -3
# 期望看到 NotoSansCJK-Regular.ttc 里包含 "Noto Sans CJK SC"
```

`fc-match` 的输出是**最终生效的字体**，比在设置里"选了某个字体"更可信（设置只是偏好，fontconfig 可能另有规则）。

---

## 3. 修复：让中文优先用 SC（简体）字形

### 方案 1：写用户级 fontconfig 规则（推荐，可回滚）

```bash
mkdir -p ~/.config/fontconfig
cat > ~/.config/fontconfig/fonts.conf <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="lang" compare="contains"><string>zh</string></test>
    <edit name="family" mode="prepend" binding="strong">
      <string>Noto Sans CJK SC</string>
    </edit>
  </match>
  <match target="pattern">
    <test name="lang" compare="contains"><string>zh</string></test>
    <edit name="family" mode="append" binding="weak">
      <string>Noto Serif CJK SC</string>
    </edit>
  </match>
</fontconfig>
EOF
fc-cache -f
fc-match sans-serif:lang=zh     # 期望：Noto Sans CJK SC
```

**本机已应用并验证（2026-10-24）**：

```text
$ fc-match sans-serif:lang=zh
NotoSansCJK-Regular.ttc: "Noto Sans CJK SC" "Regular"     ← 改前是 "Noto Sans CJK JP"
$ fc-match serif:lang=zh
NotoSansCJK-Regular.ttc: "Noto Sans CJK SC" "Regular"
$ fc-list | grep -c "CJK SC"
16
```

注意：**已经打开的浏览器/终端可能仍用旧字体**（它们在启动时缓存了字体集），重启应用或新开窗口才会完全生效。

回滚：删掉 `~/.config/fontconfig/fonts.conf`，再 `fc-cache -f`。

### 方案 2：补装简体专用字体

```bash
sudo apt install fonts-noto-cjk fonts-noto-cjk-extra
# 或更轻的思源/文泉驿：
sudo apt install fonts-wqy-microhei fonts-wqy-zenhei
```

### 方案 3：GNOME 设置里改

`设置 → 外观 → 字体` 改成 `Noto Sans CJK SC`。注意：这只改桌面 UI 的默认族，**不会**影响浏览器/终端里按 `lang=zh` 的匹配——所以方案 1 更彻底。

---

## 4. 发虚 / 粗体缺失

```bash
# 当前渲染参数
gsettings get org.gnome.desktop.interface text-scaling-factor   # 应为 1.0
gsettings get org.gnome.desktop.interface font-antialiasing     # 常见：grayscale / rgba
gsettings get org.gnome.desktop.interface font-hinting          # 常见：slight
```

- **缩放 1.25 时字发虚**：优先调字体大小，而不是继续拉 `text-scaling-factor`（非整数缩放会让字形重采样）。
- **粗体缺失**：`fc-list | grep -i "CJK.*Bold"`，没有就装 `fonts-noto-cjk-extra`。
- **等宽字体里的中文**：终端需要显式配置 fallback（如 `Noto Sans Mono CJK SC`），否则中文宽度不齐。

---

## 5. 无效尝试

- **在 GNOME 设置里反复换字体**：只影响 UI 默认族，`fc-match sans-serif:lang=zh` 可能依然是 JP。
- **删掉所有日文字体**：会影响其他应用，而且下次更新又回来；用 fontconfig 规则更精准。
- **改 `/etc/fonts/fonts.conf`**：全局且升级会被覆盖，用户级 `~/.config/fontconfig/fonts.conf` 更安全。
- **把 dpi 改成 96**：Wayland 下 DPI 由合成器缩放决定，改 X11 dpi 无效。

---

## 6. 速查

| 症状 | 先看 |
|---|---|
| 中文是日式字形 | `fc-match sans-serif:lang=zh` 是否 JP |
| 字发虚 | `text-scaling-factor`、`font-hinting` |
| 粗体没了 | `fc-list \| grep -i Bold` |
| 终端中文不对齐 | 等宽字体是否含 CJK |
| 某应用字体和别的不一样 | 该应用是否自带字体目录（Electron/浏览器） |

## 7. 经验

1. **`fc-match` 是唯一可信的"实际字体"**，设置面板只是偏好。
2. **CJK 是一个大字体文件（.ttc）含多语言子族**，装一个包不等于用对子族，要靠 fontconfig 明确指定 `SC`。
3. **用户级规则优先于系统级**，升级不会丢。
4. **缩放问题别用字体的办法解决**：先确认缩放是不是 1.25，再谈字体。

---

## 5. 坑：`strong prepend` 会劫持拉丁字族（Arial → NotoSansCJK.ttc）

### 症状

为了让中文优先用 SC 字形，写下这条规则：

```xml
<match target="pattern">
  <test name="lang" compare="contains"><string>zh</string></test>
  <edit name="family" mode="prepend" binding="strong">
    <string>Noto Sans CJK SC</string>
  </edit>
</match>
```

之后**任何**字体请求都会落到 `NotoSansCJK-Regular.ttc`：

```bash
$ fc-match Arial
NotoSansCJK-Regular.ttc: "Noto Sans CJK SC" "Regular"
$ fc-match Segoe UI
NotoSansCJK-Regular.ttc: "Noto Sans CJK SC" "Regular"
```

正常应该是 `LiberationSans-Regular.ttf`（Arial 的度量别名）。

### 根因

- 规则里**只有 `lang` 测试，没有 `family` 测试**；
- `binding="strong"` 表示这个字族必须保留在最前面，不会被后续匹配去掉；
- 而 `LANG=zh_CN.UTF-8` 时，fontconfig 会给几乎所有应用的字体请求带上 `lang=zh`。

于是拉丁字族请求也被顶上了 CJK 字体。GNOME 系应用（Pango）能正常渲染 Noto CJK 的拉丁字形，所以症状不明显；但**老渲染器**（见下一节的 Steam）处理 `.ttc` 集合时有坑。

### 怎么判断（A/B 对照，别靠猜）

```bash
# 1) 现在会不会被劫持
fc-match Arial            # 期望 LiberationSans-Regular.ttf
fc-match 'sans-serif:lang=en'   # 期望 Noto Sans / DejaVu，而不是 CJK ttc

# 2) 把用户配置移开再测一次，确认是不是它
mv ~/.config/fontconfig/fonts.conf /tmp/fonts.conf.off
fc-cache -f >/dev/null
fc-match Arial
mv /tmp/fonts.conf.off ~/.config/fontconfig/fonts.conf
```

### 修法：给规则加字族限定

```xml
<!-- 只对「通用无衬线」生效 -->
<match target="pattern">
  <test name="lang" compare="contains"><string>zh</string></test>
  <test name="family" compare="eq"><string>sans-serif</string></test>
  <edit name="family" mode="prepend" binding="strong">
    <string>Noto Sans CJK SC</string>
  </edit>
</match>

<!-- 显式请求 CJK 字族时也优先 SC -->
<match target="pattern">
  <test name="lang" compare="contains"><string>zh</string></test>
  <test name="family" compare="contains"><string>CJK</string></test>
  <edit name="family" mode="prepend" binding="strong">
    <string>Noto Sans CJK SC</string>
  </edit>
</match>
```

验证：

```bash
fc-match Arial                  # → LiberationSans-Regular.ttf  ✅
fc-match 'sans-serif:lang=zh-cn' # → Noto Sans CJK SC（中文需求保留）✅
```

---

## 6. Steam 更新窗口中文变 ◆ 方块（应用内正常）

### 症状

启动 Steam 更新时弹出的小窗口（标题 `Steam`、一个进度条）：

```
◆◆◆◆ Steam...
◆◆◆◆◆◆◆◆◆◆...
      [◆◆]
```

`Steam...` 能正常显示，但中文全是菱形；**进入 Steam 应用后界面完全正常**。

### 定位过程

1. 更新窗口不是 GTK/zenity：`~/.steam/debian-installation/ubuntu12_32/steam`（bootstrap 二进制）里同时有
   `Updating Steam...` 和本地化 token `#SteamBootstrapper_UpdatingSteam`，
   说明**它自绘并自己本地化**，中文 locale 下渲染“正在更新 Steam...”；
2. 菱形数量对得上：「正在更新」4 个字 → 4 个 ◆，「Steam...」是 ASCII 所以正常；
3. 系统字体没问题：用 Pango + `Ubuntu Sans 11` 渲染同一句中文完全正常；
4. 应用内界面用的是 Steam 自带的 `clientui/fonts/GoNotoKurrent-Regular.ttf`（CEF 加载），所以不受影响。

结论：**Steam 的 bootstrap 自绘渲染器没有 CJK 字形**，与 fontconfig、系统字体无关。
（先试过给 Steam 加 `FONTCONFIG_FILE` 优先 TTF 字体——无效，那针对的是 `.ttc` 处理问题，不是缺字形。）

### 解法：让 bootstrap 走英文

```bash
cp /usr/share/applications/steam.desktop ~/.local/share/applications/steam.desktop  # 或从上游复制
# 把 Exec 改成：
# Exec=env LANG=C.UTF-8 LANGUAGE=en /usr/games/steam %U
sed -i 's|^Exec=/usr/games/steam|Exec=env LANG=C.UTF-8 LANGUAGE=en /usr/games/steam|' \
  ~/.local/share/applications/steam.desktop
update-desktop-database ~/.local/share/applications
```

要点：

- **只影响对话框文案**，Steam 界面语言不变——界面语言是按账号存在
  `~/.steam/steam/userdata/<id>/config/localconfig.vdf`，不读 `LANG`；
- 验证：下次 Steam 客户端更新时，那个窗口应该变成英文 `Updating Steam...`；
- 回滚：删掉用户级 `steam.desktop`，恢复 deb 自带的同名文件或软链接即可。

这是 Valve 侧的问题（bootstrap 不支持 CJK 渲染），本地只能绕过。
