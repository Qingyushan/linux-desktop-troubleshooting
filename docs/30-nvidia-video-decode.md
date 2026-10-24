# NVIDIA 硬解：浏览器为什么用不上、什么能用

> 返回索引：[README](../README.md) ｜ 相关：[26-fonts.md](26-fonts.md)（字体）、[30 编号说明] ｜ 本机：Ubuntu 26.04.1 / GNOME 50.1 Wayland / GTX 1060 Mobile（580.178.04）+ HD 630

## 症状

- 在 Firefox（snap）里看 B 站视频，NVIDIA 面板「视频解码器占用」始终 0%，`nvidia-smi pmon` 里 `dec` 列是 `-`；
- 播放时 Firefox 各进程合计 CPU 约 75–80%（1080p 软解）；
- 显卡驱动本身没问题（游戏、`vainfo` 都正常）。

## 结论先行

| 方案 | 结果 |
| --- | --- |
| Firefox（snap） | ❌ 沙箱内 0 个 VA-API 驱动，看不到 `/dev/nvidia*` |
| Firefox（deb 158） | ❌ 自己的门禁 `Hw codec disabled by gfxVars`（要求硬件合成/GPU 进程） |
| Chrome 156 | ❌ 硬编码跳过：`Should skip nVidia device named: nvidia-drm` |
| 改用 HD 630（Intel iGPU） | ❌ 驱动可用，但浏览器/mpv 都拿不到它的 VA-API 上下文 |
| **mpv + NVDEC** | ✅ `Using hardware decoding (nvdec)` |

一句话：**浏览器路线在本机走不通，播放器可以。**

---

## 1. 先确认不是驱动问题

```bash
$ LIBVA_DRIVER_NAME=nvidia vainfo --display drm --device /dev/dri/renderD129
libva info: Trying to open /usr/lib/x86_64-linux-gnu/dri/nvidia_drv_video.so
libva info: va_openDriver() returns 0
vainfo: Driver version: VA-API NVDEC driver [direct backend]
  VAProfileH264High   : VAEntrypointVLD
  VAProfileHEVCMain   : VAEntrypointVLD
  VAProfileVP9Profile0: VAEntrypointVLD
```

期望：出现 `VA-API NVDEC driver`。说明 `nvidia-vaapi-driver`（`nvidia_drv_video.so`）能把 VA-API 翻译成 NVDEC。

> 注意：GTX 1060 是 Pascal，**不支持 AV1** 解码；vainfo 里没有 `VAProfileAV1Profile0` 属正常。

## 2. 三个坑，逐条

### 坑 1：Firefox snap 拿不到驱动

```bash
$ find /snap/firefox/current/gpu-2404 -name "*_drv_video.so" | wc -l
0
$ snap connections firefox | grep -i nvidia
（无输出）
```

snap 的 `gpu-2404` 内容包里没有任何 VA-API 驱动，Firefox 也没有 `nvidia` 接口，看不到 `/dev/nvidia*`。**snap 版天生做不到硬解**，换 deb 版才有意义。

### 坑 2：Firefox deb 被自己的门禁挡住

装了 Mozilla 官方 deb（158.0.1），环境变量与 pref 都配齐：

```bash
LIBVA_DRIVER_NAME=nvidia NVD_BACKEND=direct MOZ_DISABLE_RDD_SANDBOX=1 firefox
# user.js:
#   media.ffmpeg.vaapi.enabled=true
#   media.ffmpeg.vaapi.drm-device=/dev/dri/renderD129
```

播放时抓 `MOZ_LOG=PlatformDecoderModule:5`：

```
[RDD ...] D/PlatformDecoderModule Hw codec disabled by gfxVars for AV_CODEC_ID_H264
[RDD ...] D/PlatformDecoderModule Hw codec disabled by gfxVars for AV_CODEC_ID_VP9
[RDD ...] D/PlatformDecoderModule Hw codec disabled by gfxVars for AV_CODEC_ID_AV1
```

**每个编码都禁用**，说明是全局开关，不是codec问题。`gfxVars::HardwareVideoDecoding` 要求硬件合成（GPU 进程），而这台机器上 Firefox 没有 GPU 进程（WebRender 走软件路径）。

试过但没用：

- `gfx.webrender.all=true`、`layers.acceleration.force-enabled=true`
- `gfx.x11-egl.force-enabled=true`、`widget.dmabuf.force-enabled=true`
- `MOZ_ENABLE_WAYLAND=0`（X11 回退）

门禁都没打开。**这条路线放弃。**

### 坑 3：Chrome 直接跳过 NVIDIA 设备

装了 Chrome 156，带标准参数：

```bash
google-chrome-stable \
  --enable-features=VaapiVideoDecoder,VaapiVideoEncoder,VaapiVideoDecodeLinuxGL,VaapiIgnoreDriverChecks \
  --disable-features=UseChromeOSDirectVideoDecoder \
  --disable-gpu-sandbox \
  --enable-logging=stderr --v=1
```

日志里永远是：

```
WARNING:media/gpu/vaapi/vaapi_wrapper.cc:130] Should skip nVidia device named: nvidia-drm
VERBOSE1:media/gpu/vaapi/vaapi_wrapper.cc:1750] GetHandle(): Either
  VADisplayStateSingleton::PreSandboxInitialization() hasn't been called or that method failed
```

Chromium 的 `vaapi_wrapper` 里**硬编码跳过 NVIDIA 的 DRM 设备**，`VaapiIgnoreDriverChecks` 也不影响这一步。**这条路也放弃。**

### 附带：换 HD 630 也不行

驱动层面是好的：

```bash
$ LIBVA_DRIVER_NAME=iHD vainfo --display drm --device /dev/dri/renderD128
vainfo: Driver version: Intel iHD driver for Intel(R) Gen Graphics - 26.1.2
  H264 / HEVCMain / HEVCMain10 / VP9 / JPEG ...
```

但：

- Chrome 用 `LIBVA_DRIVER_NAME=iHD` / `--ozone-platform=x11` 都一样卡在 `PreSandboxInitialization`（它只枚举到 `nvidia-drm` 就跳过了）；
- mpv 用 `--hwdec=vaapi` 报 `iHD_drv_video.so init failed`——因为**显示输出接在 NVIDIA 上**，渲染上下文是 NVIDIA 的 EGL，Intel VA-API 在里面起不来（`DRI_PRIME=1` 也不行）。

这台机器的显示链路在独显上，iGPU 只适合做计算/编码，不适合给浏览器解码用。

---

## 3. 真正可用的方案：mpv + NVDEC

NVDEC 走 `libnvcuvid`，**不经过 VA-API**，所以绕开了上面所有坑。

```bash
# ~/.config/mpv/mpv.conf
hwdec=nvdec
vo=gpu
keep-open=yes
```

验证（期望输出 `Using hardware decoding (nvdec).`）：

```bash
$ mpv --no-audio --frames=60 /path/to/video.webm
Using hardware decoding (nvdec).
```

设为默认播放器：

```bash
xdg-mime default mpv.desktop video/mp4 video/x-matroska video/webm \
  video/x-msvideo video/quicktime video/x-flv video/mp2t video/mpeg video/ogg
xdg-mime query default video/mp4     # 期望：mpv.desktop
```

效果：1080p 硬解后 Firefox/Chrome 那 30–40% 的 CPU 占用不再出现；看视频时 `nvidia-smi pmon` 的 `dec` 列会 > 0。

## 回滚

```bash
# 恢复默认播放器（GNOME 自带）
xdg-mime default org.gnome.Showtime.desktop video/mp4 video/x-matroska video/webm
rm ~/.config/mpv/mpv.conf
```

## 经验

- **“显卡能解码” ≠ “浏览器能解码”**。浏览器用的是 VA-API 前端，而 VA-API 在 NVIDIA 上要靠 `nvidia-vaapi-driver` 桥；FF 要硬件合成、Chrome 直接黑名单跳过——两头都不通。
- 排查时先抓**浏览器自己的日志**（FF 的 `MOZ_LOG=PlatformDecoderModule:5`、Chrome 的 `--enable-logging=stderr --v=1`），不要靠猜“是不是 AV1”。
- 混合显卡笔记本上换 iGPU 解码不是万能药：**显示接在哪个 GPU 上，渲染上下文就在哪个 GPU 上**，另一个 GPU 的 VA-API 未必能插进去。
- 真要硬解，优先用原生播放器（mpv/ffmpeg 的 `--hwdec=nvdec`），别在浏览器上耗。
