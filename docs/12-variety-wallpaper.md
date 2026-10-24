# Variety：壁纸轮换不折腾

> 返回索引：[README](../README.md) ｜ 原始位置：§12.2


- 打开 Variety，在 **Sources** 里添加本地壁纸文件夹；在线源可按需启用 Bing / Unsplash。
- 在 **Preferences** 里设置切换间隔；NVIDIA 机器如果切换动画卡顿，关闭特效或选“无效果”。
- 想让壁纸登录后自动轮换，在 Preferences 勾选开机启动；不想自启就取消。
- 命令行快捷操作：

  ```bash
  variety --set /home/qys/图片/wallpaper.jpg   # 立刻设置某张
  variety --next          # 下一张
  variety --pause         # 暂停轮换
  variety --preferences   # 打开设置
  ```

- 在线源下载的图在 `~/.config/variety/Downloaded`；想离线就只用本地文件夹。
