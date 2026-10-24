# 触摸板：点击不灵、滚动方向反、打字误触、手势

> 返回索引：[README](../README.md) ｜ 相关：[13-daily-tips.md](13-daily-tips.md) ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 设置项 | 当前值 |
|---|---|
| `tap-to-click`（轻触点击） | **true** |
| `natural-scroll`（自然滚动） | **true** |
| `speed` | **0.0** |
| `disable-while-typing` | **true** |
| 输入栈 | `libinput`（Wayland 会话），`/usr/share/libinput/` 下有 quirks 规则 |

> 关键前提：这是 **Wayland** 会话。`xinput`、`synclient`、`xset` 这些 X11 工具**用不了**，别照抄 X11 教程。

---

## 1. 先分清"设置问题"还是"驱动问题"

| 现象 | 类型 | 判断 |
|---|---|---|
| 能移动但点不动 | 设置（`tap-to-click` 关了） | `gsettings get ...` |
| 完全不动 | 驱动/硬件 | `libinput list-devices` 能否列出 |
| 打字时光标乱跳 | `disable-while-typing` | 设置 |
| 滚动方向反 | `natural-scroll` | 设置 |
| 三指/四指手势无效 | GNOME 手势支持范围 | 见第 4 节 |

---

## 2. 设置类：gsettings 一条命令搞定

```bash
# 轻触点击
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true

# 滚动方向（自然滚动 = 手指方向与内容移动一致）
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false

# 指针速度（-1.0 ~ 1.0，0 为默认）
gsettings set org.gnome.desktop.peripherals.touchpad speed 0.2

# 打字时禁用触摸板
gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true

# 双指/三指点击行为（GNOME 50 支持）
gsettings set org.gnome.desktop.peripherals.touchpad click-method 'fingers'
```

改完立即生效，不需要重启会话。

---

## 3. 驱动类：确认触摸板存在

```bash
# 设备是否被识别（I2C 触摸板常见路径）
cat /proc/bus/input/devices | grep -A4 -i "touchpad\|trackpad"
# 期望：Name="...Touchpad..."、Handlers=mouseX eventY

# 内核日志
dmesg | grep -iE "i2c|touchpad|elan|synaptics" | tail -20

# libinput 视角（需要权限，可能要用 sudo）
libinput list-devices | grep -A8 -i touchpad
```

**完全不动 + `dmesg` 里没有触摸板设备** → 是硬件/内核层面没认到，不是设置问题。常见处理：

- BIOS 里触摸板被禁用；
- 内核参数 `i8042.nopnp` / `psmouse.synaptics_intertouch=1`（老机型）；
- 内核升级后驱动缺失（回滚内核，见 [22](22-nvidia-kernel-update.md)）。

---

## 4. GNOME 手势能做什么

GNOME 50 内置（Wayland）：

| 手势 | 动作 |
|---|---|
| 三指左右滑 | 切换工作区 |
| 三指上滑 | 打开活动视图 / 应用网格 |
| 四指左右滑 | 切换工作区（部分机型） |
| 双指滚动 / 捏合 | 滚动、缩放（应用内） |

**不支持的**：自定义手势（如"三指下滑 = 最小化"）需要第三方扩展（如 Gesture Improvements），GNOME 本身不给。

---

## 5. libinput quirks：厂商适配补丁

很多触摸板的"漂移/误触"是厂商固件特性，libinput 用 quirks 文件处理：

```bash
ls /usr/share/libinput/
# 本机：10-generic-keyboard.quirks、10-generic-mouse.quirks 等

# 自己加针对性规则（放 /etc/libinput/local-overrides.quirks）：
sudo tee /etc/libinput/local-overrides.quirks >/dev/null <<'EOF'
[Touchpad disable while typing]
MatchName=*ELAN*
AttrEventCodeDisable=BTN_TOUCH;
EOF
```

改完 `sudo systemctl restart systemd-logind` 或重新登录。

---

## 6. 无效尝试

- **`xinput list` / `synclient`**：Wayland 下不存在这些接口，会直接找不到设备。
- **`gsettings` 改完以为要重启**：触摸板设置即时生效。
- **装 `synaptics` 驱动**：现代内核用 `libinput` 统一处理，装 synaptics 反而可能冲突。
- **反复插拔 USB 鼠标**：与内置触摸板无关（除非是 USB 触摸板）。

---

## 7. 速查

| 症状 | 先看 |
|---|---|
| 点不动 | `gsettings get ... tap-to-click` |
| 完全不动 | `/proc/bus/input/devices`、`dmesg` |
| 打字误触 | `disable-while-typing` |
| 滚动反向 | `natural-scroll` |
| 手势无效 | GNOME 支持范围（第 4 节） |
| 漂移/跳 | libinput quirks |

## 8. 经验

1. **先确认会话类型**：X11 教程（xinput/synclient）在 Wayland 下全废。
2. **`gsettings` 是设置层的唯一入口**，改完即生效，不需要重启。
3. **"完全不动"和"点不动"是两个完全不同的问题**，前者查内核。
4. **quirks 是处理厂商固件特性的正规渠道**，别用脚本轮询/强制复位。
