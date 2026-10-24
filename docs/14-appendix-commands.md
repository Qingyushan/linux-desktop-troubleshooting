# 附录：常用检查命令

> 返回索引：[README](../README.md) ｜ 原始位置：§10


```bash
# 当前应用环境（确认参数是否生效）
pid=$(pgrep -f '^/usr/bin/deepseek-harness-desktop$')
tr '\0' '\n' < /proc/$pid/environ | grep -E 'WEBKIT|GDK|LIBGL'

# WebKit 进程
ps -eo pid,rss,cmd | grep -E 'WebKit(Web|Network)Process'

# 窗口（XWayland 下）
xwininfo -root -tree | grep -iE 'DSH Tauri|Pet'

# 服务与端口
ss -tlnp | grep 3080

# 证书链
openssl s_client -connect store.steampowered.com:443 -servername store.steampowered.com </dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# NSS 库
certutil -L -d sql:$HOME/.pki/nssdb
certutil -L -d sql:$HOME/snap/firefox/common/.mozilla/firefox/<profile>

# DSH 日志
tail -50 ~/.local/share/dsh-tauri/logs/desktop.log
grep -iE 'error|fail|warn' ~/.local/share/dsh-tauri/logs/desktop.log | tail

# 插件
cat ~/.local/share/dsh-tauri/plugin-errors.json
dsh --profile tauri --dump-config | grep -i <plugin>
```

---
