import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

/**
 * Quiet Startup：登录后一段时间内，把指定应用的窗口直接最小化。
 *
 * 为什么用扩展而不是 xdotool：
 *   QQ / 微信走 XWayland，还能用 xdotool 操控；但 DSH 桌面端是原生 Wayland 窗口，
 *   Wayland 下任何外部进程都无法最小化别人的窗口（没有 wlr-foreign-toplevel 之类接口），
 *   只有跑在 GNOME Shell 进程里的扩展能调用 MetaWindow.minimize()。
 *
 * 工作方式：
 *   - enable() 时（登录时 shell 启动阶段）记下截止时间，此后 loginWindowSeconds 秒内，
 *     凡是新创建、且 wm_class / app_id 命中 apps 列表的窗口 -> 立刻 minimize()。
 *   - 每 2 秒复查一次：窗口被应用自己"弹回来"就再压回去（最多 maxRetries 次）；
 *     如果窗口当前有焦点（说明是你手动还原并正在用），就不抢。
 *   - 到期自动停止复查，之后手动启动这些应用完全不受影响。
 *   - shell 启动早于 autostart 应用，所以 QQ/微信/DSH 的窗口一定在期限内创建。
 *
 * 配置：~/.config/quiet-startup/config.json（可选，改完 disable/enable 生效）
 * 日志：/tmp/quiet-startup.log
 */

const CONFIG_PATH = GLib.build_filenamev([
    GLib.get_home_dir(), '.config', 'quiet-startup', 'config.json',
]);
const LOG_PATH = '/tmp/quiet-startup.log';

const DEFAULTS = {
    loginWindowSeconds: 150,
    maxRetries: 3,
    // 匹配标识：先精确比对 wm_class / app_id，再做「长度 >= 4 且被包含」的模糊匹配。
    // 短标识（如 qq）只做精确匹配，避免误伤 qqmusic 之类。
    apps: [
        'deepseek-harness-desktop',
        'deepseek-harness',
        'dsh-tauri',
        'qq',
        'wechat',
        'weixin',
        'xwechat',
    ],
};

export default class QuietStartupExtension extends Extension {
    enable() {
        this._cfg = this._readConfig();
        this._apps = this._cfg.apps.map(a => `${a}`.toLowerCase());
        this._maxRetries = Math.max(0, Number(this._cfg.maxRetries) || 0);
        this._deadline = GLib.get_monotonic_time()
            + Math.max(1, Number(this._cfg.loginWindowSeconds) || DEFAULTS.loginWindowSeconds) * 1000000;
        this._states = new WeakMap();
        this._logText = '';
        this._timer = 0;
        this._windowSignal = 0;

        this._log(`== enable: apps=${this._apps.join(',')} window=${this._cfg.loginWindowSeconds}s`);
        this._logExisting();

        this._windowSignal = global.display.connect('window-created', (_display, win) => {
            // 过了登录窗口期就彻底不管，避免几小时后新开聊天窗口也被压下去
            if (GLib.get_monotonic_time() > this._deadline)
                return;
            try {
                this._log(`created: ${this._names(win).join('|') || '(no name)'}`);
                this._minimize(win, 'created');
            } catch (e) {
                this._log(`error(created): ${e.message ?? e}`);
            }
        });

        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => this._retry());
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
        this._log('== disable');
    }

    // ---- 逻辑 ----

    _retry() {
        if (GLib.get_monotonic_time() > this._deadline) {
            this._timer = 0;
            this._log('disarm: login window elapsed');
            return GLib.SOURCE_REMOVE;
        }
        try {
            for (const actor of global.get_window_actors()) {
                const win = actor.meta_window;
                if (!win || !this._states.has(win))
                    continue;
                this._minimize(win, 'retry');
            }
        } catch (e) {
            this._log(`error(retry): ${e.message ?? e}`);
        }
        return GLib.SOURCE_CONTINUE;
    }

    _minimize(win, reason) {
        if (!win)
            return;
        if (GLib.get_monotonic_time() > this._deadline)
            return;
        if (win.is_skip_taskbar?.() === true)
            return;

        const app = this._match(win);
        if (!app) {
            // 不是目标应用；但如果之前认过它（重名改动之类），就别再动
            return;
        }

        const st = this._state(win);

        if (win.minimized) {
            // 已经是最小化状态，什么都不用做
            return;
        }

        if (reason !== 'created') {
            if (st.retries > this._maxRetries)
                return;
            if (win.has_focus?.() === true) {
                // 有焦点 = 你刚刚手动还原并在用，不抢
                return;
            }
        }

        try {
            win.minimize();
            st.retries++;
            this._log(`minimize(${reason}#${st.retries}): app=${app} names=${this._names(win).join('|')}`);
        } catch (e) {
            this._log(`error(minimize): ${e.message ?? e}`);
        }
    }

    _match(win) {
        const names = this._names(win);
        // 1) 精确匹配：Wayland 的 app_id 与 X11 的 WM_CLASS 大小写已统一成小写
        for (const token of this._apps) {
            if (names.includes(token))
                return token;
        }
        // 2) 包含匹配：覆盖 com.tencent.wechat / wechat-beta 这类变体；
        //    长度 >= 4 才启用，避免 "qq" 命中 "qqmusic" 之类误伤
        for (const token of this._apps) {
            if (token.length < 4)
                continue;
            if (names.some(name => name.includes(token)))
                return token;
        }
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

    _state(win) {
        let st = this._states.get(win);
        if (!st) {
            st = {retries: 0};
            this._states.set(win, st);
        }
        return st;
    }

    _logExisting() {
        try {
            const names = global.get_window_actors()
                .map(actor => this._names(actor.meta_window).join('|'))
                .filter(name => name !== '');
            this._log(`existing windows: ${names.join(' , ') || '(none)'}`);
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
            return merged;
        } catch {
            return {...DEFAULTS};
        }
    }

    _log(line) {
        try {
            const now = new Date().toTimeString().slice(0, 8);
            if (this._logText.length > 40000)
                this._logText = this._logText.slice(-20000);
            this._logText += `[${now}] ${line}\n`;
            GLib.file_set_contents(LOG_PATH, this._logText);
        } catch {
            // 日志失败不影响功能
        }
    }
}
