# DSH 桌面端画面冻结（本次最耗时的问题）

> 返回索引：[README](../README.md) ｜ 原始位置：§5 + §12.6 ｜ 相关脚本：`../scripts/restart-dsh.sh`、`../scripts/set-scale.py`


### 现象

- 页面能正常显示第一帧，之后**只有拖动窗口边缘（resize）时才刷新**；
- 按钮、输入框都能交互，状态也在变，但画面停在上一帧；
- 打开设置菜单时尤其容易“卡死”；
- AppImage 与 deb 都出现过，deb 明显轻很多。

### 环境特征

- Tauri + WebKitGTK 2.52.6；
- NVIDIA 580 驱动 + XWayland（应用设置 `force_xwayland: true`）；
- 软件渲染（llvmpipe + `WEBKIT_SKIA_ENABLE_CPU_RENDERING=1`）**仍然复现**。

> 上游跟踪：#789 / #791 已解释 AppImage 的 GTK 钩子强制 XWayland；本机 deb + `force_xwayland` 的补充报告见 [#1226](https://github.com/dsh-tauri/deepseek-harness-desktop/issues/1226)。

### 试错矩阵

| # | 尝试 | 结果 | 说明 |
| - | - | - | - |
| 1 | `WEBKIT_DISABLE_DMABUF_RENDERER=1` | 无效 | 排除 DMA-BUF 花屏类问题，但不是本症状 |
| 2 | `WEBKIT_DISABLE_COMPOSITING_MODE=1` | 无效 | 关闭加速合成也不恢复持续刷新 |
| 3 | 1+2 组合 | 无效 | 最“重”的组合也不行 |
| 4 | `WEBKIT_FORCE_VBLANK_TIMER=1` | 无效 | 强制定时器帧同步也不行 |
| 5 | 1+2+4 组合 | 无效 | 本次 AppImage 的最终尝试 |
| 6 | 软件渲染（`LIBGL_ALWAYS_SOFTWARE=1` + `WEBKIT_SKIA_ENABLE_CPU_RENDERING=1`） | 无效 | **关键结论：不是 GPU 光栅化问题** |
| 7 | 全局 `backdrop-filter: none` + 主题菜单模糊补丁 | 无效 | 排除 CSS 毛玻璃拖垮合成器 |
| 8 | 关闭宠物窗口、窗口模糊/半透明 | 无效 | 排除 Tauri 窗口特效 |
| 9 | X11 / Wayland 原生切换 | 无效 | 排除单一后端 |
| 10 | 换 **.deb**（同版本 0.25.0） | **明显改善** | 同版本不同打包，表现不同 |

### 根因判断（诚实版）

未能 100% 定位到 WebKit 内部的具体 bug。可以确定的是：

- 不是“画不出来”（软件渲染仍能画第一帧）；
- 不是单纯 DMA-BUF / 加速合成；
- 更像是 **WebKitGTK UI 进程的帧呈现/帧同步在 NVIDIA + XWayland 组合下停摆**，resize 强制触发一次 present；
- AppImage 与 deb 的差异（运行时、环境、启动方式）会放大或掩盖这个问题。

### 有效的工程做法

1. **先换包**：AppImage → deb，成本最低、收益最大。
2. 保留“按症状加参数”的能力，而不是一次性全上：
   - 花屏/黑屏/闪烁 → `WEBKIT_DISABLE_DMABUF_RENDERER=1`
   - 只有 resize 刷新 → `WEBKIT_FORCE_VBLANK_TIMER=1`
   - 崩溃/静默退出 → 最后才 `WEBKIT_DISABLE_COMPOSITING_MODE=1`
3. 每次只加一个变量，并在重启后检查：

```bash
pid=$(pgrep -f '^/usr/bin/deepseek-harness-desktop$')
tr '\0' '\n' < /proc/$pid/environ | grep WEBKIT
```

4. 不要相信“应用内重启”会带上新环境；它通常 `exec` 自身，环境还是旧的。
5. 不要用全局 CSS/主题补丁长期兜底；验证完要还原。

### 性能代价（重要）

| 变量 | 代价 | 建议 |
| - | - | - |
| `WEBKIT_DISABLE_COMPOSITING_MODE=1` | **最大**：滚动/动画/视频/Canvas 全部 CPU 光栅化，CPU 与耗电上升，动画不顺滑 | 非必要不用 |
| `WEBKIT_DISABLE_DMABUF_RENDERER=1` | 中等：共享内存多一次拷贝，视频/动画有开销 | 只在花屏/黑屏时用 |
| `WEBKIT_FORCE_VBLANK_TIMER=1` | 很小：定时器代替 DRM vblank，可能轻微帧抖动 | 只在 resize 刷新时用 |

---



---

## 补充：日常使用要点（原 §12.6）


- 优先用 `.deb` 版；AppImage 的 GTK 钩子会强制 `GDK_BACKEND=x11`，在 NVIDIA + Wayland 上更容易触发“只有 resize 才刷新”。
- 出现停绘时，临时拖一下窗口边缘能刷新，但这只是绕过；长期用 `WEBKIT_FORCE_VBLANK_TIMER=1` 启动，或参考 [05-dsh-render-freeze.md](05-dsh-render-freeze.md)。
- 图标空白时跑 `scripts/fix-dsh-icon.sh`；不要再全局改 `~/.local/share/themes` 或应用 CSS，升级会覆盖。
- 看日志：

  ```bash
  tail -50 ~/.local/share/dsh-tauri/logs/desktop.log
  ```

- 宠物置顶和渲染流畅有取舍：`force_xwayland=false` 更接近原生 Wayland，但宠物置顶可能失效；按需选。
- 想登录后安静启动（窗口最小化、只留托盘）见 12.3，别为此改 `force_xwayland`。
