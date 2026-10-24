#!/usr/bin/env python3
"""在桌面客户端未运行时，把外观设置写进 ~/.local/share/dsh-tauri/.store.dat。

用法：dsh-set-appearance [--blur on|off] [--opacity 0-100]
不带的参数保持原值。客户端运行时会用内存里的值覆盖该文件，所以要在客户端关闭时执行。
"""
import json, pathlib, sys, shutil, datetime

store = pathlib.Path.home() / ".local/share/dsh-tauri/.store.dat"
args = sys.argv[1:]
if not store.exists():
    sys.exit(f"找不到 {store}")

want_blur = None
want_opacity = None
i = 0
while i < len(args):
    if args[i] == "--blur" and i + 1 < len(args):
        want_blur = args[i + 1].lower() in ("on", "true", "1", "yes")
        i += 2
    elif args[i] == "--opacity" and i + 1 < len(args):
        want_opacity = max(0, min(100, int(args[i + 1])))
        i += 2
    else:
        sys.exit(__doc__)

data = json.loads(store.read_text())
app = data.setdefault("setting", {}).setdefault("appearance", {})
before = dict(app)
if want_blur is not None:
    app["blur"] = want_blur
if want_opacity is not None:
    app["opacity"] = want_opacity

backup = store.with_name(f".store.dat.bak-{datetime.datetime.now():%Y%m%d-%H%M%S}")
shutil.copy2(store, backup)
store.write_text(json.dumps(data, ensure_ascii=False, indent=2))
print("appearance:", before, "→", app)
print("备份:", backup)
