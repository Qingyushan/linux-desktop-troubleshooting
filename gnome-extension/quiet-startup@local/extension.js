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
 *   - 已处理过的窗口被应用自己弹回来：只在窗口创建后的「首次压制 + focusGraceSeconds」
 *     之内无视焦点继续压（QQ 自动登录会自己把主面板顶上来几次）；超过这个短暂宽限期
 *     后，**只要窗口拿到焦点就永久让位**（记进 yielded），之后再不碰它；
 *   - 同一窗口两次压制之间至少间隔 minRetryGapSeconds，避免 500ms 扫描把应用连击；
 *   - 最多压 maxRetries 次；
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
    loginWindowSeconds: 300,
    // 从 enable 起多久之内"第一次看到"的窗口才归扩展管（秒）。
    // 超时后新出现的窗口一律不管：那是用户自己开的，不是开机自启。
    startupPhaseSeconds: 60,
    // 进程比 shell 晚启动超过这个秒数，就当作用户自己开的，一律不管（秒）
    autostartProcessGraceSeconds: 120,
    maxRetries: 5,
    // 从"首次压制"起算的短暂宽限（秒）：这段时间内无视焦点继续压，
    // 覆盖 QQ / 微信 自动登录后把窗口顶回来的几下。
    // 超过它之后，窗口一旦有焦点就永久让位，避免用户使用时被反复收回。
    focusGraceSeconds: 10,
    // 同一窗口两次压制的最小间隔（秒），防止 500ms 扫描把应用连击。
    minRetryGapSeconds: 2,
    // 窗口名标识：先精确比对 wm_class / app_id，再做「长度 >= 4 且被包含」的模糊匹配
    // （覆盖 com.tencent.wechat / wechat-beta 这类变体；短标识如 qq 只做精确匹配）
    // DSH 客户端已改为无头服务启动（见 docs/17），不在此列；
    // 若你改成开机自启客户端并希望它安静进托盘，把 'deepseek-harness-desktop'
    // 和 'deepseek-harness' 加回 apps，并把 '/opt/qq/qq' 那种进程片段也补上。
    apps: [
        'qq',
        'wechat',
        'weixin',
        'xwechat',
    ],
    // 进程命令行片段（小写），pid 兜底匹配用
    processes: [
        '/opt/qq/qq',
        'wechat',
    ],
};

export default class QuietStartupExtension extends Extension {
    enable() {
        this._cfg = this._readConfig();
        this._apps = this._cfg.apps.map(a => `${a}`.toLowerCase());
        this._procs = this._cfg.processes.map(p => `${p}`.toLowerCase());
        this._maxRetries = Math.max(0, Number(this._cfg.maxRetries) || 0);
        this._phaseUs = Math.max(0, Number(this._cfg.startupPhaseSeconds) || 0) * 1000000;
        this._procGraceSec = Math.max(0, Number(this._cfg.autostartProcessGraceSeconds) || 0);
        this._procVerdicts = new Map();
        this._phaseDeadline = GLib.get_monotonic_time() + this._phaseUs;
        this._yieldedPids = new Set();
        this._graceUs = Math.max(0, Number(this._cfg.focusGraceSeconds) || 0) * 1000000;
        this._minGapUs = Math.max(0, Number(this._cfg.minRetryGapSeconds) || 0) * 1000000;
        this._deadline = GLib.get_monotonic_time()
            + Math.max(1, Number(this._cfg.loginWindowSeconds) || DEFAULTS.loginWindowSeconds) * 1000000;
        this._states = new WeakMap();
        this._pidCache = new Map();
        this._logText = '';
        this._timer = 0;
        this._windowSignal = 0;

        const uptime = this._shellUptimeSeconds();
        const late = uptime > Math.max(60, this._phaseUs / 1000000 * 2);
        this._log(`== enable: apps=${this._apps.join(',')} procs=${this._procs.join(',')} window=${this._cfg.loginWindowSeconds}s shellUptime=${uptime.toFixed(0)}s${late ? ' (late: 不接管任何窗口)' : ''}`);
        if (late) {
            // 会话中途启用（例如装了新版本被 shell 重载）：只记录，不动任何窗口
            this._phaseDeadline = GLib.get_monotonic_time() - 1;
            this._deadline = GLib.get_monotonic_time() - 1;
        } else {
            this._logExisting();
        }

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

        const pid = this._pid(win);
        if (pid && this._yieldedPids.has(pid))
            return;

        const handled = this._states.get(win);
        if (handled && handled.retries > 0) {
            // 用户已经接管过这个窗口：永久不再碰它
            if (handled.yielded)
                return;
            // maxRetries 是"总共最多压几次"（含首次）
            if (handled.retries >= this._maxRetries)
                return;

            const now = GLib.get_monotonic_time();
            const inGrace = handled.firstMs > 0 && (now - handled.firstMs) < this._graceUs;
            // 宽限期过后，窗口一拿到焦点就认定"用户在用"，永久让位。
            // 宽限期内不看焦点，只用来覆盖应用自动登录后自己顶回来的几下。
            if (!inGrace && win.has_focus?.() === true) {
                handled.yielded = true;
                if (pid)
                    this._yieldedPids.add(pid);
                this._log(`yield: 窗口已由用户接管，之后不再压制该程序的任何窗口 names=${this._names(win).join('|') || '-'} pid=${pid || '-'}`);
                return;
            }
            // 防连击：两次压制之间至少隔 minRetryGapSeconds
            if (handled.lastMs > 0 && (now - handled.lastMs) < this._minGapUs)
                return;
        }

        const hit = this._match(win);
        if (!hit)
            return;

        // 进程级判定：比 shell 晚启动太久 = 用户自己开的程序，整个进程都不管
        if (pid) {
            let verdict = this._procVerdicts.get(pid);
            if (verdict === undefined) {
                const delay = this._procStartDelaySeconds(pid);
                verdict = delay >= 0 && delay > this._procGraceSec;
                this._procVerdicts.set(pid, verdict);
                if (verdict) {
                    this._log(`skip-process: pid=${pid} 比 shell 晚启动 ${delay.toFixed(0)}s（>${this._procGraceSec}s），视为用户自己打开`);
                }
            }
            if (verdict)
                return;
        }

        // 启动阶段之外的"新窗口"一律不管：那是用户自己开的，不是开机自启
        if (GLib.get_monotonic_time() > this._phaseDeadline && !(this._states.get(win)?.retries > 0)) {
            if (!this._lateLogged) {
                this._lateLogged = true;
                this._log(`skip-late: 启动阶段已过，不再接管新窗口 names=${this._names(win).join('|') || '-'}`);
            }
            return;
        }

        const state = this._state(win);
        try {
            win.minimize();
            state.retries++;
            state.lastMs = GLib.get_monotonic_time();
            if (state.firstMs === 0)
                state.firstMs = state.lastMs;
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
            state = {retries: 0, lastMs: 0, firstMs: 0, yielded: false};
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

    /** 当前 GNOME Shell 进程已运行的秒数；取不到时返回 0（当作"刚登录"）。 */
    _shellUptimeSeconds() {
        try {
            const [okUp, upBytes] = GLib.file_get_contents('/proc/uptime');
            const [okStat, statBytes] = GLib.file_get_contents('/proc/self/stat');
            if (!okUp || !okStat)
                return 0;
            const uptime = parseFloat(new TextDecoder().decode(upBytes).split(' ')[0]);
            const stat = new TextDecoder().decode(statBytes);
            // comm 可能含空格/括号，从最后一个 ')' 之后开始切
            const rest = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
            const startTicks = Number(rest[19]); // 第 22 字段 starttime
            if (!Number.isFinite(uptime) || !Number.isFinite(startTicks))
                return 0;
            return Math.max(0, uptime - startTicks / 100);
        } catch {
            return 0;
        }
    }

    /** 进程比 GNOME Shell 晚启动多少秒；取不到返回 -1（当作"按原样处理"）。 */
    _procStartDelaySeconds(pid) {
        if (!pid)
            return -1;
        try {
            const [okUp, upBytes] = GLib.file_get_contents('/proc/uptime');
            const [okStat, statBytes] = GLib.file_get_contents(`/proc/${pid}/stat`);
            if (!okUp || !okStat)
                return -1;
            const uptime = parseFloat(new TextDecoder().decode(upBytes).split(' ')[0]);
            const stat = new TextDecoder().decode(statBytes);
            const rest = stat.slice(stat.lastIndexOf(')') + 2).split(' ');
            const startTicks = Number(rest[19]);
            if (!Number.isFinite(uptime) || !Number.isFinite(startTicks))
                return -1;
            const procUptime = uptime - startTicks / 100;
            return this._shellUptimeSeconds() - procUptime;
        } catch {
            return -1;
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
