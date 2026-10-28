import Foundation
import WinSDK

import MooringsCore

// version is the build's version, shown by the version probe and, later, the tray's About item.
let version = "dev"

// perMonitorAwareV2 is DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2, a cast macro Swift does not
// import.
var perMonitorAwareV2: DPI_AWARENESS_CONTEXT? { DPI_AWARENESS_CONTEXT(bitPattern: -4) }

// ProbeError is a bad probe command line.
enum ProbeError: Error, CustomStringConvertible {
    case missingValue(String)
    case badValue(String, String)
    case unknownFlag(String)

    // description says what was wrong with the command line.
    var description: String {
        switch self {
        case .missingValue(let flag): "\(flag) needs a value"
        case .badValue(let flag, let value): "\(flag) does not take \(value)"
        case .unknownFlag(let flag): "unknown flag \(flag)"
        }
    }
}

// ProbeOptions holds the probe command line.
struct ProbeOptions {
    // probe is the probe to run, or nil to run the app.
    var probe: String?
    // minAspect is the ratio a monitor needs to count as ultrawide. Only probes set it.
    var minAspect = Layout.minAspect
    // noDelta places without the border correction, the place probe's negative control.
    var noDelta = false
    // seconds is how long the moor probe runs its loop.
    var seconds = 10.0
    // paused writes a paused choices file, the moor probe's negative control.
    var paused = false
    // noFilter keeps every hooked event, the events probe's negative control.
    var noFilter = false
    // noApps builds the menu with no running apps, the menu probe's negative control.
    var noApps = false
    // pid names the process whose window the nudge probe moves.
    var pid: DWORD?
    // frame is where the nudge probe moves the window.
    var frame: Frame?

    // init parses args, the command line without the program name.
    init(_ args: [String]) throws {
        var rest = args[...]
        while let flag = rest.popFirst() {
            switch flag {
            case "--probe":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                probe = value
            case "--min-aspect":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let n = Double(value), n > 0 else { throw ProbeError.badValue(flag, value) }
                minAspect = n
            case "--no-delta":
                noDelta = true
            case "--paused":
                paused = true
            case "--no-filter":
                noFilter = true
            case "--no-apps":
                noApps = true
            case "--seconds":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let n = Double(value), n > 0 else { throw ProbeError.badValue(flag, value) }
                seconds = n
            case "--pid":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let n = DWORD(value) else { throw ProbeError.badValue(flag, value) }
                pid = n
            case "--frame":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                let n = value.split(separator: ",").compactMap { Double($0) }
                guard n.count == 4, n[2] > 0, n[3] > 0 else { throw ProbeError.badValue(flag, value) }
                frame = Frame(x: n[0], y: n[1], w: n[2], h: n[3])
            default:
                throw ProbeError.unknownFlag(flag)
            }
        }
    }
}

// Probe runs one mechanism, prints lines the Windows workflow checks, and returns the exit code.
typealias Probe = @Sendable (ProbeOptions) -> Int32

// probes maps each probe name to its function.
let probes: [String: Probe] = [
    "version": probeVersion,
    "monitors": probeMonitors,
    "list": probeList,
    "place": probePlace,
    "moor": probeMoor,
    "nudge": probeNudge,
    "events": probeEvents,
    "menu": probeMenu,
    "tray": probeTray,
]

// probeVersion prints the version and the DPI awareness the thread runs with.
func probeVersion(_: ProbeOptions) -> Int32 {
    print("version: \(version)")
    let v2 = AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext(), perMonitorAwareV2)
    print("dpi: \(v2 ? "per-monitor-v2" : "other")")
    return 0
}

// probeMonitors prints one line per monitor and the index of the ultrawide among them.
func probeMonitors(_ opts: ProbeOptions) -> Int32 {
    let monitors = Monitor.all()
    for (i, m) in monitors.enumerated() {
        print("monitor \(i): full \(pixels(m.full)) usable \(pixels(m.usable))",
              "primary \(m.primary)")
    }
    let index = Layout.ultrawide(monitors.map(\.full), minAspect: opts.minAspect)
    print("ultrawide: \(index.map(String.init) ?? "none")")
    return monitors.isEmpty ? 1 : 0
}

// probeList prints one line per movable window, front-most first, and which one has focus.
func probeList(_ opts: ProbeOptions) -> Int32 {
    let (windows, focused) = WinWindows.scan(screens: .current(minAspect: opts.minAspect))
    for w in windows {
        print("window \(hex(w.id)): \(w.bundle) frame \(pixels(w.frame))",
              "main \(w.isMain) fullscreen \(w.isFullScreen)")
    }
    print("focused: \(focused.map { hex($0.id) } ?? "none")")
    return 0
}

// probePlace moves the front Notepad window twice and prints each read-back and its insets.
func probePlace(_ opts: ProbeOptions) -> Int32 {
    let windows = WinWindows.scan(screens: .current(minAspect: opts.minAspect)).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix("\\notepad.exe") }) else {
        print("place: no notepad window")
        return 1
    }
    let placer = WinWindows()
    placer.corrects = !opts.noDelta
    for target in [Frame(x: 100, y: 100, w: 800, h: 600), Frame(x: 300, y: 200, w: 640, h: 480)] {
        placer.move(pad.id, to: target)
        print("asked: \(pixels(target)) placed: \(placer.frame(pad.id).map(pixels) ?? "gone")")
    }
    let d = WinWindows.hwnd(pad.id).flatMap(WinWindows.insets) ?? Insets()
    print("delta: \(Int(d.left)) \(Int(d.top)) \(Int(d.right)) \(Int(d.bottom))",
          "elevated \(placer.elevated.contains(pad.id))")
    return 0
}

// probeMoor pins the front Notepad to the left top slot in a fresh choices file, runs the pass loop
// for the given seconds, and prints each move and release with its time, then the final frames.
func probeMoor(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("moor: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix("\\notepad.exe") }) else {
        print("moor: no notepad window")
        return 1
    }
    let store = Store()
    let choices = Choices(slots: [.leftTop: pad.bundle], widths: Widths(left: 40, right: 30),
                          paused: opts.paused)
    do {
        try store.save(choices)
    } catch {
        print("moor: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    print("start at \(stamp(App.now)) pinned \(hex(pad.id)) paused \(app.anchors.choices.paused)")
    app.moved = { move, t, got in
        print("move \(hex(move.id)) at \(stamp(t)) to \(pixels(move.frame))",
              "got \(got.map(pixels) ?? "gone")")
    }
    app.released = { id, t in print("released \(hex(id)) at \(stamp(t))") }
    app.run(until: App.now + opts.seconds)
    let use = app.anchors.inUse(wide)
    print("strip: \(pixels(Geometry.regions(wide, use.left, use.right).left))")
    print("channel: \(pixels(app.anchors.channel(wide)))")
    for w in WinWindows.scan(screens: screens).windows {
        print("final \(hex(w.id)) pid \(WinWindows.hwnd(w.id).map(WinWindows.processID) ?? 0)",
              "frame \(pixels(w.frame))")
    }
    return 0
}

// probeEvents runs the pass loop with no anchored app for the given seconds, and prints each
// window event that woke it, each pass, and the counts of events hooked and kept.
func probeEvents(_ opts: ProbeOptions) -> Int32 {
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("events: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    app.watcher.filters = !opts.noFilter
    var kept = 0, passes = 0
    print("start at \(stamp(App.now))")
    app.noticed = { kind, id, t in
        kept += 1
        print("event \(kind) \(hex(id)) at \(stamp(t))")
    }
    app.passed = { t, moves in
        passes += 1
        print("pass at \(stamp(t)) moves \(moves)")
    }
    app.run(until: App.now + opts.seconds)
    print("raw events: \(app.watcher.raw) passed: \(app.watcher.passed) kept: \(kept) passes: \(passes)")
    return 0
}

// probeMenu prints the tray menu the saved choices and the running windows build, one entry per
// line, indented by depth, with [x] beside a checked entry.
func probeMenu(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    let running = opts.noApps ? [] : WinWindows.scan(screens: screens).windows.map(\.bundle)
    printMenu(Tray.menu(choices: Store().load(), running: running, atLogin: LoginItem.enabled))
    return 0
}

// printMenu prints items and their folders, depth levels in.
func printMenu(_ items: [MenuItem], depth: Int = 0) {
    let indent = String(repeating: "  ", count: depth)
    for item in items {
        guard !item.title.isEmpty else {
            print("menu \(indent)-")
            continue
        }
        print("menu \(indent)[\(item.checked ? "x" : " ")] \(item.title)\(item.enabled ? "" : " (off)")")
        printMenu(item.submenu, depth: depth + 1)
    }
}

// probeTray adds the tray icon, chooses the front Notepad for the left top slot and then Pause
// through the menu's commands, prints the saved choices after each, and removes the icon.
func probeTray(_ opts: ProbeOptions) -> Int32 {
    let windows = WinWindows.scan(screens: .current(minAspect: opts.minAspect)).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix("\\notepad.exe") }) else {
        print("tray: no notepad window")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("tray: \(error)")
        return 1
    }
    let tray = Tray(app: App(store: store, minAspect: opts.minAspect))
    print("icon: \(Tray.loadIcon() == nil ? "none" : "loaded")")
    print("added: \(tray.show())")
    tray.perform(.slot(.leftTop, pad.bundle))
    print("saved left top: \(store.load().slots[.leftTop] ?? "")")
    tray.perform(.pause)
    print("saved paused: \(store.load().paused)")
    tray.hide()
    return 0
}

// probeNudge moves the front window of a process to a frame, the way an owner or an app would.
func probeNudge(_ opts: ProbeOptions) -> Int32 {
    guard let pid = opts.pid, let frame = opts.frame else {
        print("nudge: needs --pid and --frame")
        return 2
    }
    let screens = Screens.current(minAspect: opts.minAspect)
    let hwnd = WinWindows.topLevel().first {
        WinWindows.processID($0) == pid && WinWindows.describe($0, screens: screens) != nil
    }
    guard let hwnd else {
        print("nudge: no window for pid \(pid)")
        return 1
    }
    let id = WinWindows.id(hwnd)
    WinWindows().move(id, to: frame)
    print("nudged \(hex(id)) at \(stamp(App.now)) to \(pixels(frame))")
    return 0
}

// hex formats a window id the way the list probe does.
func hex(_ id: WindowID) -> String {
    "0x" + String(id, radix: 16)
}

// stamp formats a time to the millisecond.
func stamp(_ t: Double) -> String {
    String(format: "%.3f", t)
}

// pixels formats f as whole x, y, w and h, the same in every locale.
func pixels(_ f: Frame) -> String {
    "\(Int(f.x)) \(Int(f.y)) \(Int(f.w)) \(Int(f.h))"
}

// Monitor is one display as Windows reports it, in top-left physical pixels.
struct Monitor {
    // full is rcMonitor, the whole display.
    var full: Frame
    // usable is rcWork, the display without the taskbar.
    var usable: Frame
    // primary is true for the display that holds the origin.
    var primary: Bool

    // all returns every monitor in EnumDisplayMonitors order.
    static func all() -> [Monitor] {
        let found = MonitorList()
        let context = LPARAM(Int(bitPattern: Unmanaged.passUnretained(found).toOpaque()))
        _ = EnumDisplayMonitors(nil, nil, { handle, _, _, context in
            let raw = UnsafeRawPointer(bitPattern: Int(context))!
            let found = Unmanaged<MonitorList>.fromOpaque(raw).takeUnretainedValue()
            var info = MONITORINFO()
            info.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
            if GetMonitorInfoW(handle, &info) {
                let primary = info.dwFlags & DWORD(MONITORINFOF_PRIMARY) != 0
                let full = Frame(info.rcMonitor), usable = Frame(info.rcWork)
                found.monitors.append(Monitor(full: full, usable: usable, primary: primary))
            }
            return true
        }, context)
        return withExtendedLifetime(found) { found.monitors }
    }
}

// MonitorList collects monitors inside the EnumDisplayMonitors callback.
final class MonitorList {
    // monitors holds the monitors found so far.
    var monitors: [Monitor] = []
}

extension Frame {
    // init converts a Win32 RECT.
    init(_ r: RECT) {
        self.init(x: Double(r.left), y: Double(r.top), w: Double(r.right - r.left),
                  h: Double(r.bottom - r.top))
    }
}
