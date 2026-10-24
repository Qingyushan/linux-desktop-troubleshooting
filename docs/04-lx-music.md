# LX Music 与自定义音源

> 返回索引：[README](../README.md) ｜ 原始位置：§4 + §12.5


### 安装

官方 GitHub Release 的 deb（2.12.6），装完菜单出现 **LX Music**。

### 自定义源的存储格式（重点）

LX Music 的“自定义源”不是放在 `sources/` 目录，而是存在：

```
~/.config/lx-music-desktop/LxDatas/user_api.json
```

结构：

```json
{
  "userApis": [
    {
      "id": "user_api_xxx_<timestamp>",
      "name": "星海音乐源",
      "description": "...",
      "author": "...",
      "homepage": "...",
      "version": "v3.2.15",
      "allowShowUpdateAlert": false,
      "script": "gz_<base64(zlib(script))>"
    }
  ]
}
```

- `script` 是 `zlib.deflate` 后 base64，前缀 `gz_`；
- 当前启用的源写在 `LxData/config_v2.json` 的 `setting["common.apiSource"]`；
- 源脚本必须以 `/* ... @name ... */` 块注释开头，应用会解析 `@name/@version/@author/@homepage`；
- 成功加载时主进程日志会出现 `load api <名字>`，并创建一个隐藏的 **User api** WebKit 窗口。

### 本次加载的源

来自公开仓库 [pdone/lx-music-source](https://github.com/pdone/lx-music-source)：

- 星海音乐源 v3.2.15（网易/QQ/酷狗/酷我/咪咕/汽水，musicUrl + lyric + pic）
- 全豆要聚合音源 v9.3（多链路回退）
- 幻音音源 v3

### 风险提示

- 这些是第三方脚本，以应用权限运行、会访问第三方接口；安装前应检查是否为明文、有无 `eval/require/fs/child_process` 等可疑调用（本次三个源均为明文，未发现明显问题）。
- 音源依赖的接口随时可能失效；曲库版权归各平台，请仅作试听并支持正版。
- 应用更新可能覆盖 profile，来源失效后需重新导入。

---



---

## 补充：日常使用要点（原 §12.5）


- 自定义源在 `~/.config/lx-music-desktop/LxDatas/user_api.json`，升级 / 重装前先备份：

  ```bash
  cp ~/.config/lx-music-desktop/LxDatas/user_api.json \
     ~/lx-user-api-backup-$(date +%F).json
  ```

- 换源后如果没声音，先看主进程日志有没有 `load api <名字>`；没有就重新导入。
- 第三方音源可能失效、可能带风险；只试用，支持正版。
