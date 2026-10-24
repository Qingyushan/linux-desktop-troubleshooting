import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

/**
 * Quiet Startup：登录后一段时间内，把指定应用的窗口最小化（只留托盘图标）。
 *
 * 为什么用扩展而不是 xdotool：
 *   QQ / 微信 / DSH 桌面端现在都是原生 Wayland 窗口；Wayland 没有 wlr-foreign-toplevel
 *   之类的接口，外部进程（xdotool / wmctrl）只能操控 XWayland 窗口。只有跑在 GNOME
 *   Shell 进程里的扩展能调用 MetaWindow.minimize()。
 *
 * 匹配为什么有两条路：
 *   1) 窗口名（wm_class / app_id）—— QQ 走 XWayland，窗口一创建就有 WM_CLASS；
 *   2) 进程 pid -> /proc/<pid>/cmdline —— 原生 Wayland 窗口在 window-created 触发时
 *      app_id 往往还没提交（实测日志里是 `(no name)`），此时只能靠 pid 判断归属。
 *   另外每 500ms 把所有窗口重扫一遍，这样 app_id 晚一两帧提交也能补上。
 *
 * 时序：登录窗口期内（默认 150 秒）
 *   - 首次命中：立刻 minimize()，即使窗口自带焦点（登录时 autostart 窗口通常有焦点）；
 *   - 已处理过的窗口被应用自己弹回来：窗口没有焦点时再压，最多 maxRetries 次；
 *   - 到期彻底放手，之后手动开这些应用、开新聊天窗口都不受影响。
 *
 * 配置：~/.config/quiet-startup/config.json（改完 disable/enable 生效，不用重登）
 * 日志：/tmp/quiet-startup.log
 */

const CONFIG_PATH = GLib.build_filenamev([
    GLib.get_home_dir(), '.config', 'quiet-startup', 'config.json',
]);
const LOG_PATH = '/tmp/quiet-startup.log';
const SCAN_INTERVAL_MS = 500;
const NAME_RECHECK_MS = 250;

const DEFAULTS = {
    loginWindowSeconds: 150,
    maxRetries: 3,
    // 窗口名标识：先精确比对 wm_class / app_id，再做「长度 >= 4 且被包含」的模糊匹配
    // （覆盖 com.tencent.wechat / wechat-beta 这类变体；短标识如 qq 只做精确匹配）
    apps: [
        'deepseek-harness-desktop',
        'deepseek-harness',
        'dsh-tauri',
        'qq',
        'wechat',
        'weixin',
        'xwechat',
    ],
    // 进程命令行片段（小写），pid 兜底匹配用
    processes: [
        '/opt/qq/qq',
        'wechat',
        'deepseek-harness-desktop',
    ],
};

export default class QuietStartupExtension extends Extension {
    enable() {
        this._cfg = this._readConfig();
        this._apps = this._cfg.apps.map(a => `${a}`.toLowerCase());
        this._procs = this._cfg.processes.map(p => `${p}`.toLowerCase());
        this._maxRetries = Math.max(0, Number(this._cfg.maxRetries) || 0);
        this._deadline = GLib.get_monotonic_time()
            + Math.max(1, Number(this._cfg.loginWindowSeconds) || DEFAULTS.loginWindowSeconds) * 1000000;
        this._states = new WeakMap();
        this._pidCache = new Map();
        this._logText = '';
        this._timer = 0;
        this._windowSignal = 0;

        this._log(`== enable: apps=${this._apps.join(',')} procs=${this._procs.join(',')} window=${this._cfg.loginWindowSeconds}s`);
        this._logExisting();

        this._windowSignal = global.display.connect('window-created', (_display, win) => {
            if (this._expired())
                return;
            try {
                this._log(`created: pid=${this._pid(win)} names=${this._names(win).join('|') || '-'}`);
                this._consider(win, 'created');
                // 原生 Wayland 的 app_id 可能晚几帧才提交，补一次快速复查
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, NAME_RECHECK_MS, () => {
                    try {
                        this._consider(win, 'recheck');
                    } catch {
                        // 窗口可能已销毁
                    }
                    return GLib.SOURCE_REMOVE;
                });
            } catch (e) {
                this._log(`error(created): ${e.message ?? e}`);
            }
        });

        this._timer = GLib.timeout_add(GLib.PRIORITY_DEFAULT, SCAN_INTERVAL_MS, () => this._scan());
    }

    disable() {
        if (this._timer) {
            GLib.source_remove(this._timer);
            this._timer = 0;
        }
        if (this._windowSignal) {
            try {
                global.display.disconnect(this._windowSignal);
            } catch {
                // 忽略：display 可能已销毁
            }
            this._windowSignal = 0;
        }
        this._states = null;
        this._pidCache = null;
        this._log('== disable');
    }

    // ---- 调度 ----

    _scan() {
        if (this._expired()) {
            this._timer = 0;
            this._log('disarm: login window elapsed');
            return GLib.SOURCE_REMOVE;
        }
        try {
            for (const actor of global.get_window_actors()) {
                const win = actor.meta_window;
                if (!win || win.minimized)
                    continue;
                this._consider(win, 'scan');
            }
        } catch (e) {
            this._log(`error(scan): ${e.message ?? e}`);
        }
        return GLib.SOURCE_CONTINUE;
    }

    // ---- 判定与最小化 ----

    _consider(win, reason) {
        if (!win || this._expired())
            return;
        if (win.is_skip_taskbar?.() === true)
            return;
        if (win.minimized)
            return;

        const handled = this._states.get(win);
        if (handled && handled.retries > 0) {
            // 处理过：只在应用自己把窗口弹回来、且用户没在动它时再压
            if (handled.retries > this._maxRetries)
                return;
            if (win.has_focus?.() === true)
                return;
        }

        const hit = this._match(win);
        if (!hit)
            return;

        const state = this._state(win);
        try {
            win.minimize();
            state.retries++;
            this._log(`minimize(${reason}#${state.retries}): ${hit.kind}=${hit.key} pid=${this._pid(win)} names=${this._names(win).join('|') || '-'}`);
        } catch (e) {
            this._log(`error(minimize): ${e.message ?? e}`);
        }
    }

    _match(win) {
        const names = this._names(win);
        // 1) 精确匹配窗口名
        for (const token of this._apps) {
            if (names.includes(token))
                return {kind: 'app', key: token};
        }
        // 2) 包含匹配（仅长标识，避免 qq 命中 qqmusic）
        for (const token of this._apps) {
            if (token.length < 4)
                continue;
            if (names.some(name => name.includes(token)))
                return {kind: 'app', key: token};
        }
        // 3) pid 兜底：读 /proc/<pid>/cmdline
        const pidKey = this._pidMatch(win);
        if (pidKey)
            return {kind: 'process', key: pidKey};
        return null;
    }

    _names(win) {
        const out = [];
        const push = value => {
            if (typeof value !== 'string')
                return;
            const name = value.toLowerCase().trim();
            if (name !== '' && !out.includes(name))
                out.push(name);
        };
        for (const getter of ['get_wm_class', 'get_wm_class_instance',
            'get_gtk_application_id', 'get_sandboxed_app_id']) {
            try {
                if (typeof win[getter] === 'function')
                    push(win[getter]());
            } catch {
                // 某些窗口没有这个属性，忽略
            }
        }
        return out;
    }

    _pid(win) {
        try {
            const pid = typeof win.get_pid === 'function' ? win.get_pid() : 0;
            return typeof pid === 'number' && pid > 0 ? pid : 0;
        } catch {
            return 0;
        }
    }

    _pidMatch(win) {
        const pid = this._pid(win);
        if (!pid)
            return null;
        if (this._pidCache.has(pid))
            return this._pidCache.get(pid);

        let hit = null;
        try {
            const [ok, bytes] = Gio.File.new_for_path(`/proc/${pid}/cmdline`).load_contents(null);
            if (ok && bytes && bytes.length > 0) {
                const cmdline = new TextDecoder().decode(bytes).replace(/\0/g, ' ').toLowerCase();
                hit = this._procs.find(token => cmdline.includes(token)) ?? null;
            }
        } catch {
            // 进程可能刚好退出
        }
        this._pidCache.set(pid, hit);
        return hit;
    }

    _state(win) {
        let state = this._states.get(win);
        if (!state) {
            state = {retries: 0};
            this._states.set(win, state);
        }
        return state;
    }

    _expired() {
        return GLib.get_monotonic_time() > this._deadline;
    }

    _logExisting() {
        try {
            const lines = global.get_window_actors().map(actor => {
                const win = actor.meta_window;
                if (!win)
                    return null;
                return `pid=${this._pid(win)} names=${this._names(win).join('|') || '-'}`;
            }).filter(line => line !== null);
            this._log(`existing windows: ${lines.join(' , ') || '(none)'}`);
        } catch (e) {
            this._log(`error(existing): ${e.message ?? e}`);
        }
    }

    // ---- 配置 / 日志 ----

    _readConfig() {
        try {
            const file = Gio.File.new_for_path(CONFIG_PATH);
            const [, bytes] = file.load_contents(null);
            if (!bytes || bytes.length === 0)
                return {...DEFAULTS};
            const parsed = JSON.parse(new TextDecoder().decode(bytes));
            const merged = {...DEFAULTS, ...(parsed && typeof parsed === 'object' ? parsed : {})};
            if (!Array.isArray(merged.apps) || merged.apps.length === 0)
                merged.apps = DEFAULTS.apps;
            if (!Array.isArray(merged.processes) || merged.processes.length === 0)
                merged.processes = DEFAULTS.processes;
            return merged;
        } catch {
            return {...DEFAULTS};
        }
    }

    _log(line) {
        try {
            const now = new Date().toTimeString().slice(0, 8);
            if (this._logText.length > 60000)
                this._logText = this._logText.slice(-30000);
            this._logText += `[${now}] ${line}\n`;
            GLib.file_set_contents(LOG_PATH, this._logText);
        } catch {
            // 日志失败不影响功能
        }
    }
}
