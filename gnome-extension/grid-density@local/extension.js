import Gio from 'gi://Gio';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// 网格参数集中在 config.json，改完只需 disable/enable 扩展，不必重新登录。
const DEFAULTS = {iconSize: 80, rows: 5, columns: 10};

export default class GridDensityExtension extends Extension {
    enable() {
        this._saved = null;
        this._grid = null;
        this._cfg = this._readConfig();
        try {
            this._apply();
            this._monitorsId = Main.layoutManager.connect(
                'monitors-changed', () => this._apply());
        } catch (e) {
            logError(e, '[grid-density] enable');
        }
    }

    disable() {
        try {
            if (this._monitorsId) {
                Main.layoutManager.disconnect(this._monitorsId);
                this._monitorsId = 0;
            }
            const lm = this._layout();
            if (lm && this._saved) {
                lm.fixedIconSize = this._saved.fixedIconSize;
                if (this._saved.modes !== undefined) {
                    this._grid._gridModes = this._saved.modes;
                    this._grid._currentMode = -1;
                }
                this._grid?.queue_relayout?.();
            }
        } catch (e) {
            logError(e, '[grid-density] disable');
        }
        this._saved = null;
    }

    _readConfig() {
        try {
            const file = Gio.File.new_for_path(`${this.path}/config.json`);
            const [, bytes] = file.load_contents(null);
            const parsed = JSON.parse(new TextDecoder().decode(bytes));
            return {
                iconSize: Number(parsed.iconSize) || DEFAULTS.iconSize,
                rows: Number(parsed.rows) || DEFAULTS.rows,
                columns: Number(parsed.columns) || DEFAULTS.columns,
            };
        } catch (e) {
            logError(e, '[grid-density] config');
            return {...DEFAULTS};
        }
    }

    _layout() {
        const appDisplay = Main.overview?.controls?._appDisplay ??
            Main.overview?._overview?.controls?._appDisplay;
        const grid = appDisplay?._grid;
        const lm = grid?.layout_manager;
        if (!lm)
            return null;
        if (!this._saved) {
            this._saved = {
                fixedIconSize: lm.fixedIconSize,
                modes: grid._gridModes,
            };
        }
        this._grid = grid;
        return lm;
    }

    _apply() {
        const lm = this._layout();
        if (!lm)
            return;
        lm.fixedIconSize = this._cfg.iconSize;
        this._grid._gridModes = [{rows: this._cfg.rows, columns: this._cfg.columns}];
        this._grid._currentMode = -1;
        this._grid.queue_relayout();
        log(`[grid-density] icon=${this._cfg.iconSize} columns=${lm.columnsPerPage} rows=${lm.rowsPerPage}`);
    }
}
