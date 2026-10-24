# 系统更新后黑屏 / 掉驱动：NVIDIA + 内核的恢复顺序

> 返回索引：[README](../README.md) ｜ 相关：[23-power-suspend.md](23-power-suspend.md) ｜ 原始位置：新增（覆盖面补全）

## 本机环境（实测）

| 项 | 值 |
|---|---|
| 内核 | `7.0.0-38-generic`（Ubuntu 26.04 HWE） |
| 显卡 | **NVIDIA GP106M / GeForce GTX 1060 Mobile**，`lspci -k` 显示 `Kernel driver in use: nvidia` |
| 驱动 | 闭源 `nvidia-driver-580` **580.178.04**（`nvidia-smi` 可读） |
| Secure Boot | **enabled**（`mokutil --sb-state`） |
| 会话 | Wayland（`nvidia_drm.modeset=1` 是 Wayland 下用 NVIDIA 的前提） |

---

## 1. 更新后"黑屏"其实有三种，先分清

| 类型 | 现象 | 判断 |
|---|---|---|
| **A. 内核起来但图形没起** | 黑屏、无光标，但 SSH / `Ctrl+Alt+F3` 能进 tty | 显卡驱动没加载（最常见） |
| **B. 内核都没起** | 卡在 GRUB 之后，风扇转、屏幕黑 | 内核/initramfs 问题，与显卡无关 |
| **C. 起了但掉到软件渲染** | 能进桌面，但卡顿、`glxinfo` 显示 llvmpipe | 驱动加载了但 3D 不可用 |

---

## 2. 能进 tty 时的定位（类型 A）

```bash
# 1. 显卡驱动到底加载了没
lspci -k | grep -A3 -E "VGA|3D"
# 期望：Kernel driver in use: nvidia
# 若显示 nouveau 或为空 → 驱动没加载

# 2. 内核模块是否编译成功（Secure Boot 下未签名会拒绝加载）
sudo dmesg | grep -iE "nvidia|nouveau" | tail -20
# 常见：NVRM: loading NVIDIA UNIX ... / module verification failed / Required key not available

# 3. DKMS 状态（内核升级后驱动要重新编译）
dkms status
# 期望：nvidia/580.178.04, 7.0.0-38-generic, x86_64: installed
```

**关键区别**：`module verification failed: Required key not available` = Secure Boot 拒绝了未签名模块；这时不是"驱动坏了"，是签名问题。

---

## 3. 恢复顺序（从便宜到贵）

### 方案 1：重新加载模块（不用重启）

```bash
sudo modprobe -r nvidia_drm nvidia_modeset nvidia
sudo modprobe nvidia_drm modeset=1
systemctl restart gdm    # 或 sudo systemctl restart display-manager
```

### 方案 2：临时用 nomodeset 进桌面

GRUB 菜单按 `e`，在 `linux` 行末加 `nomodeset`，`Ctrl+X` 启动。能进桌面说明是显卡驱动问题——这只是**诊断手段**，不是长期方案（NVIDIA 下 nomodeset 会掉到软件渲染）。

### 方案 3：回滚到上一个内核

```bash
ls /boot/vmlinuz-*                       # 看有哪些内核
sudo grub-reboot "Advanced options for Ubuntu>Ubuntu, with Linux 7.0.0-37-generic"   # 名字照抄 grub 菜单
sudo reboot
# 永久默认：改 /etc/default/grub 的 GRUB_DEFAULT，再 sudo update-grub
```

回滚只解决"内核与驱动不匹配"，如果是驱动包本身有问题（方案 4）。

### 方案 4：回滚驱动版本

```bash
apt-cache policy nvidia-driver-580 | head -5     # 看有哪些可用版本
sudo apt install nvidia-driver-580=<旧版本>
# 或退回开源 nouveau（性能差但能亮）：
sudo apt remove --purge '^nvidia-.*' && sudo apt install xserver-xorg-video-nouveau
```

### 方案 5：Secure Boot 的签名问题

```bash
mokutil --sb-state        # enabled 时，第三方模块必须签名
sudo dkms status          # 若 "installed" 但加载失败，多半是签名
```

两条路：给 DKMS 模块签名（`mokutil --import`，重启时在蓝色 MOK 界面录入），或关闭 Secure Boot（BIOS 里改）。**前者更安全**，后者会削弱启动链保护。

---

## 4. 类型 C：驱动在，但 3D 掉到 llvmpipe

```bash
glxinfo -B | grep -E "OpenGL renderer|Vendor"
# 期望：NVIDIA GeForce GTX 1060
# 实际：llvmpipe (LLVM ...) → 3D 不可用

nvidia-smi     # 能跑就说明内核模块在，问题在用户态 GL
```

常见原因：`libgl1-mesa-dri` 与 `nvidia` 的 alternatives 被 mesa 抢了。

```bash
sudo update-alternatives --config glx    # 选 nvidia
```

---

## 5. 预防：更新前做三件事

1. `apt list --upgradable | grep -E "linux-image|nvidia"` —— 看到内核和驱动同时更新，**留出恢复时间**。
2. 确认 `/boot` 有空间（内核+initramfs 会占 100–200 MB）：`df -h /boot`。
3. 记下当前内核：`uname -r`，回滚时用来指定 GRUB 菜单项。

---

## 6. 无效尝试

- **反复重装驱动但内核还是旧的**：DKMS 会针对当前内核编译，问题在内核不在包。
- **在 Wayland 会话里 `nvidia-xconfig`**：那是 X11 的配置工具，Wayland 下不生效。
- **`sudo apt purge nvidia*` 一把梭**：`nvidia*` 会匹配到 `nvidia-prime`、`nvidia-settings` 等，容易把桌面一起卸掉；用 `'^nvidia-.*'` 更精确。
- **改 `xorg.conf`**：Wayland 会话根本不读它。

---

## 7. 速查

| 症状 | 先看 |
|---|---|
| 黑屏但有 tty | `lspci -k` 的 `Kernel driver in use` |
| `dmesg` 报 module verification failed | Secure Boot / MOK 签名 |
| 更新内核后必黑 | `dkms status`（模块没为新内核编译） |
| 能进桌面但卡 | `glxinfo -B`（llvmpipe = 掉了 3D） |
| 想立刻回滚 | GRUB `grub-reboot` 指定旧内核 |

## 8. 经验

1. **黑屏先分 A/B/C**，不要一上来就重装驱动。
2. **`lspci -k` 的 "Kernel driver in use" 是最硬的证据**，比 fstab 里写什么、装了什么包都可信。
3. **Secure Boot 开启时，DKMS 模块必须签名**；这是"驱动装了却不加载"的头号原因。
4. **Wayland + NVIDIA 必须 `nvidia_drm.modeset=1`**，没有它 Wayland 会话起不来或掉回 X11。
