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
    "hotkeys": probeHotkeys,
    "hold": probeHold,
    "banner": probeBanner,
    "skip": probeSkip,
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
    app.notify = { title, body in print("notice: \(title): \(body)") }
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

// heldChord is Ctrl+Alt+Left, Left half in the built-in keymaps: the chord the hotkeys probe injects
// and the hold probe takes first.
let heldChord = (mods: UINT(0x0002 | 0x0001), vk: UINT(0x25))

// probeHotkeys binds the shortcuts from a fresh choices file, prints what was registered and
// skipped, brings the front Notepad forward, injects Ctrl+Alt+Left, runs the loop for the given
// seconds, and prints the presses received, Notepad's frame and the channel.
func probeHotkeys(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("hotkeys: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix("\\notepad.exe") }),
          let hwnd = WinWindows.hwnd(pad.id) else {
        print("hotkeys: no notepad window")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("hotkeys: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let map = Bindings(app.anchors.choices).map
    app.hotkeys.bind(map, runnable: app.actions.supports)
    defer { app.hotkeys.unbind() }
    print("table: \(map.count) registered: \(app.hotkeys.names.count) skipped: \(app.hotkeys.skipped.count)")
    for s in app.hotkeys.skipped {
        print("skipped \(s.name): \(s.reason)")
    }
    print("foreground before: \(foreground())")
    _ = bringForward(hwnd)
    print("foreground after: \(foreground()) notepad \(hex(pad.id))")
    print("before: \(pixels(pad.frame))")
    print("sent: \(press([0x11, 0x12, 0x25]))")
    app.run(until: App.now + opts.seconds)
    let pressed = app.hotkeys.pressed
    print("hotkeys received: \(pressed.isEmpty ? "none" : pressed.joined(separator: ","))")
    print("after: \(app.windows.frame(pad.id).map(pixels) ?? "gone")")
    print("channel: \(pixels(app.anchors.channel(wide)))")
    return 0
}

// probeHold takes Ctrl+Alt+Left for the given seconds, the way another program would, and prints
// whether it got the chord and how many presses reached it: the hotkeys probe's negative control.
func probeHold(_ opts: ProbeOptions) -> Int32 {
    let held = RegisterHotKey(nil, 1, heldChord.mods | WinHotkeys.noRepeat, heldChord.vk)
    print("held: \(held)")
    var got = 0
    pump(until: App.now + opts.seconds) { msg in
        if msg.message == UINT(WM_HOTKEY) {
            got += 1
        }
    }
    if held {
        _ = UnregisterHotKey(nil, 1)
    }
    print("hotkeys received: \(got)")
    return 0
}

// probeBanner shows a banner and prints its rect, the scale, the screen it centers on, whether it
// took the foreground, and whether it closed itself after the fade.
func probeBanner(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let screen = screens.wide ?? screens.usable.first else {
        print("banner: no screen")
        return 1
    }
    let before = GetForegroundWindow()
    let banner = BannerWindow(minAspect: opts.minAspect)
    banner.show("Moorings", "The banner probe shows this box, which fades after three seconds and never "
        + "takes the foreground.")
    guard let hwnd = banner.window else {
        print("banner: not shown")
        return 1
    }
    var r = RECT()
    _ = GetWindowRect(hwnd, &r)
    let exStyle = DWORD(truncatingIfNeeded: GetWindowLongPtrW(hwnd, GWL_EXSTYLE))
    print("banner: \(pixels(Frame(r))) scale \(banner.scale)")
    print("screen: \(pixels(screen))")
    print("visible: \(IsWindowVisible(hwnd)) topmost: \(exStyle & 0x8 != 0)",
          "noactivate: \(exStyle & 0x0800_0000 != 0)")
    pump(until: App.now + 1)
    print("foreground is banner: \(GetForegroundWindow() == hwnd) kept: \(GetForegroundWindow() == before)")
    print("open at 1 s: \(IsWindow(hwnd))")
    pump(until: App.now + BannerWindow.seconds + BannerWindow.fadeSeconds + 1)
    print("closed: \(!IsWindow(hwnd))")
    return 0
}

// probeSkip pins the front Notepad to the left top slot, runs the pass loop for the given seconds,
// and prints the integrity of the probe and of each window's process, each move with its read-back,
// each notice, the windows refused as elevated, and the final frames. The workflow puts Task Manager
// and a packaged app on the left strip first.
func probeSkip(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("skip: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix("\\notepad.exe") }) else {
        print("skip: no notepad window")
        return 1
    }
    let store = Store()
    let choices = Choices(slots: [.leftTop: pad.bundle], widths: Widths(left: 40, right: 30))
    do {
        try store.save(choices)
    } catch {
        print("skip: \(error)")
        return 1
    }
    print("probe integrity: \(integrity(GetCurrentProcessId()))")
    for w in windows {
        let pid = WinWindows.hwnd(w.id).map(WinWindows.processID) ?? 0
        print("window \(hex(w.id)): \(w.bundle) frame \(pixels(w.frame)) integrity \(integrity(pid))")
    }
    let app = App(store: store, minAspect: opts.minAspect)
    print("start at \(stamp(App.now)) pinned \(hex(pad.id))")
    app.moved = { move, t, got in
        print("move \(hex(move.id)) at \(stamp(t)) to \(pixels(move.frame))",
              "got \(got.map(pixels) ?? "gone")")
    }
    app.notify = { title, body in print("notice: \(title): \(body)") }
    app.run(until: App.now + opts.seconds)
    print("end at \(stamp(App.now))")
    for id in app.windows.elevated.sorted() {
        print("skipped \(hex(id)): elevated")
    }
    print("channel: \(pixels(app.anchors.channel(wide)))")
    for w in WinWindows.scan(screens: screens).windows {
        print("final \(hex(w.id)) frame \(pixels(w.frame))")
    }
    return 0
}

// integrity names the mandatory integrity level of pid's token: low, medium, high or system, or
// unknown when the token cannot be read, as a higher level's token cannot from a lower one.
func integrity(_ pid: DWORD) -> String {
    guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else {
        return "unknown"
    }
    defer { _ = CloseHandle(process) }
    var token: HANDLE?
    guard OpenProcessToken(process, DWORD(TOKEN_QUERY), &token), let token else { return "unknown" }
    defer { _ = CloseHandle(token) }
    var size: DWORD = 0
    _ = GetTokenInformation(token, TokenIntegrityLevel, nil, 0, &size)
    guard size > 0 else { return "unknown" }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 8)
    defer { buffer.deallocate() }
    guard GetTokenInformation(token, TokenIntegrityLevel, buffer, size, &size) else { return "unknown" }
    let label = buffer.load(as: TOKEN_MANDATORY_LABEL.self)
    guard let sid = label.Label.Sid, let count = GetSidSubAuthorityCount(sid)?.pointee, count > 0,
          let rid = GetSidSubAuthority(sid, DWORD(count) - 1)?.pointee else { return "unknown" }
    switch rid {
    case ..<0x2000: return "low"
    case ..<0x3000: return "medium"
    case ..<0x4000: return "high"
    default: return "system"
    }
}

// pump dispatches the thread's messages until until, passing each to each first.
func pump(until: Double, _ each: (MSG) -> Void = { _ in }) {
    let stop = SetTimer(nil, 0, UINT(max(1, ((until - App.now) * 1000).rounded(.up))), nil)
    defer { _ = KillTimer(nil, stop) }
    var msg = MSG()
    while GetMessageW(&msg, nil, 0, 0) {
        if msg.message == UINT(WM_TIMER), msg.hwnd == nil, msg.wParam == stop {
            return
        }
        each(msg)
        _ = TranslateMessage(&msg)
        _ = DispatchMessageW(&msg)
    }
}

// foreground names the foreground window the way the list probe names windows.
func foreground() -> String {
    GetForegroundWindow().map { hex(WinWindows.id($0)) } ?? "none"
}

// bringForward makes hwnd the foreground window. Windows lets only the foreground process do that,
// so when the plain call is refused it joins the foreground thread's input and asks again.
@discardableResult
func bringForward(_ hwnd: HWND) -> Bool {
    if SetForegroundWindow(hwnd) {
        return true
    }
    guard let fg = GetForegroundWindow() else { return false }
    let theirs = GetWindowThreadProcessId(fg, nil), mine = GetCurrentThreadId()
    _ = AttachThreadInput(mine, theirs, true)
    defer { _ = AttachThreadInput(mine, theirs, false) }
    return SetForegroundWindow(hwnd)
}

// press injects the keys down in order and up in reverse, and returns how many events Windows
// took. Arrow keys are sent as extended keys, as a keyboard sends them.
func press(_ keys: [WORD]) -> UINT {
    let key = { (vk: WORD, up: Bool) -> INPUT in
        var input = INPUT()
        input.type = DWORD(INPUT_KEYBOARD)
        input.ki.wVk = vk
        let extended: DWORD = (0x21...0x2E).contains(vk) ? 0x0001 : 0
        input.ki.dwFlags = extended | (up ? 0x0002 : 0)
        return input
    }
    var inputs = keys.map { key($0, false) } + keys.reversed().map { key($0, true) }
    return SendInput(UINT(inputs.count), &inputs, Int32(MemoryLayout<INPUT>.size))
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
