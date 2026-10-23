import gi, sys
gi.require_version('Gio','2.0')
from gi.repository import Gio, GLib

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
proxy = Gio.DBusProxy.new_sync(bus, Gio.DBusProxyFlags.NONE, None,
    'org.gnome.Mutter.DisplayConfig', '/org/gnome/Mutter/DisplayConfig',
    'org.gnome.Mutter.DisplayConfig', None)

state = proxy.call_sync('GetCurrentState', None, Gio.DBusCallFlags.NONE, -1, None)
serial, monitors, logical, props = state.unpack()

print('serial', serial)
for m in monitors:
    conn, vendor, product, msn = m[0]
    print('monitor', conn, vendor, product, 'modes', len(m[1]))
print('logical', [(l[0], l[1], l[2], l[4]) for l in logical])

target = float(sys.argv[1]) if len(sys.argv) > 1 else 1.25
conn_info = monitors[0]
connector = conn_info[0][0]
mode_id = conn_info[1][0][0]
# prefer the current mode
for mode in conn_info[1]:
    if 'is-current' in mode[6]:
        mode_id = mode[0]
        break

new_logical = [(0, 0, target, 0, True, [(connector, mode_id, {})])]
args = GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})', (serial, 3, new_logical, {}))
try:
    proxy.call_sync('ApplyMonitorsConfig', args, Gio.DBusCallFlags.NONE, -1, None)
    print('applied scale', target, 'on', connector, 'mode', mode_id)
except GLib.Error as e:
    print('FAILED:', e.message)
    sys.exit(1)

state2 = proxy.call_sync('GetCurrentState', None, Gio.DBusCallFlags.NONE, -1, None)
_, _, logical2, _ = state2.unpack()
print('now logical', [(l[0], l[1], l[2], l[4]) for l in logical2])
