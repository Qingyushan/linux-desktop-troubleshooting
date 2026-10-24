# Rime 雾凇拼音：输入法调顺手

> 返回索引：[README](../README.md) ｜ 原始位置：§12.1


- 切换：`Super+Space` 在“中文键盘 / Rime”之间切；`Shift` 临时中英；`1-9` 选候选，空格上屏，`Esc` 取消。
- 配置目录：`~/.config/ibus/rime`。改完配置后执行：

  ```bash
  rime_deployer --build ~/.config/ibus/rime
  ibus-daemon -drx
  ```

- 自定义短语：编辑 `~/.config/ibus/rime/custom_phrase.txt`，每行 `词<Tab>拼音<Tab>权重`：

  ```text
  深度求索	shen du qiu suo	100
  ```

  保存后重新 deploy，输入 `shendu` 之类就能看到。拼音用空格分音节，不要写声调；权重越大越靠前。

- 换回旧配置：

  ```bash
  rm -rf ~/.config/ibus/rime
  mv ~/.config/ibus/rime.bak-20261023-203129 ~/.config/ibus/rime
  ibus-daemon -drx
  ```

- 候选框不出现：先确认 `ibus engine` 输出 `rime`；再注销重登，或 `ibus-daemon -drx`。
