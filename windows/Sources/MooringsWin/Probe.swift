import Foundation
import WinSDK

import MooringsCore
import MooringsEngine
import MooringsTesting

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
    // frame is where the nudge probe moves the window, or where the place probe places it.
    var frame: Frame?
    // screen replaces the monitor walk with one monitor of this size, so the runner acts as an
    // ultrawide.
    var screen: Size?
    // mode is the display mode the modes probe switches to.
    var mode: Size?
    // reset makes the modes probe restore the display mode kept in the registry.
    var reset = false
    // noHook runs the drag probe without the mouse hook, its negative control.
    var noHook = false
    // alt holds Alt through the drag probe's drop.
    var alt = false
    // activate leaves the footprint probe's window without its pass-through bits, its negative
    // control.
    var activate = false
    // app is the end of the image path of the app whose window the probes act on: Notepad, or the
    // stand probe's window under the fake ultrawide, which Windows would not size past the desktop.
    var app = "\\notepad.exe"

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
            case "--reset":
                reset = true
            case "--app":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                app = value.lowercased()
            case "--no-hook":
                noHook = true
            case "--alt":
                alt = true
            case "--activate":
                activate = true
            case "--screen", "--mode":
                guard let value = rest.popFirst() else { throw ProbeError.missingValue(flag) }
                guard let size = Size(value) else { throw ProbeError.badValue(flag, value) }
                if flag == "--screen" {
                    screen = size
                } else {
                    mode = size
                }
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

// Size is a width and height in whole pixels, written WxH on the command line.
struct Size: Equatable {
    // w is the width.
    var w: Int
    // h is the height.
    var h: Int

    // init parses WxH, nil unless both are positive whole numbers.
    init?(_ text: String) {
        let parts = text.split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else {
            return nil
        }
        self.w = w
        self.h = h
    }

    // init builds a size from a width and height.
    init(w: Int, h: Int) {
        self.w = w
        self.h = h
    }
}

// Probe runs one mechanism, prints lines the Windows workflow checks, and returns the exit code.
typealias Probe = @Sendable (ProbeOptions) -> Int32

// probes maps each probe name to its function.
let probes: [String: Probe] = [
    "version": probeVersion,
    "monitors": probeMonitors,
    "modes": probeModes,
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
    "lift": probeLift,
    "login": probeLogin,
    "quit": probeQuit,
    "drag": probeDrag,
    "footprint": probeFootprint,
    "stand": probeStand,
    "contracts": probeContracts,
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

// probeModes prints every display mode of the primary adapter, the current one, the largest one at
// least minAspect wide, and the largest window size Windows allows. With --mode it switches to a
// mode until the next switch, and with --reset it restores the mode kept in the registry.
func probeModes(_ opts: ProbeOptions) -> Int32 {
    if opts.reset {
        let r = ChangeDisplaySettingsExW(nil, nil, nil, 0, nil)
        print("reset: \(r == 0 ? "done" : "failed \(r)")")
        return r == 0 ? 0 : 1
    }
    if let mode = opts.mode {
        var dm = DEVMODEW()
        dm.dmSize = WORD(MemoryLayout<DEVMODEW>.size)
        dm.dmPelsWidth = DWORD(mode.w)
        dm.dmPelsHeight = DWORD(mode.h)
        dm.dmFields = DWORD(DM_PELSWIDTH | DM_PELSHEIGHT)
        let r = ChangeDisplaySettingsExW(nil, &dm, nil, 0, nil)
        print("switched to \(mode.w)x\(mode.h): \(r == 0 ? "done" : "failed \(r)")")
        return r == 0 ? 0 : 1
    }
    var dm = DEVMODEW()
    dm.dmSize = WORD(MemoryLayout<DEVMODEW>.size)
    var sizes: [Size] = []
    var i: DWORD = 0
    while EnumDisplaySettingsW(nil, i, &dm) {
        let size = Size(w: Int(dm.dmPelsWidth), h: Int(dm.dmPelsHeight))
        if !sizes.contains(size) {
            sizes.append(size)
        }
        i += 1
    }
    sizes.sort { ($0.w, $0.h) < ($1.w, $1.h) }
    for s in sizes {
        print("mode \(s.w)x\(s.h) aspect \(String(format: "%.2f", Double(s.w) / Double(s.h)))")
    }
    if EnumDisplaySettingsW(nil, DWORD.max, &dm) {
        print("current: \(dm.dmPelsWidth)x\(dm.dmPelsHeight)")
    }
    let wide = sizes.filter { Double($0.w) / Double($0.h) >= opts.minAspect }.max { $0.w * $0.h < $1.w * $1.h }
    print("ultrawide mode: \(wide.map { "\($0.w)x\($0.h)" } ?? "none")")
    print("max track: \(GetSystemMetrics(SM_CXMAXTRACK)) \(GetSystemMetrics(SM_CYMAXTRACK))")
    return sizes.isEmpty ? 1 : 0
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
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }) else {
        print("place: no window of \(opts.app)")
        return 1
    }
    let placer = WinWindows()
    placer.corrects = !opts.noDelta
    let targets = opts.frame.map { [$0] }
        ?? [Frame(x: 100, y: 100, w: 800, h: 600), Frame(x: 300, y: 200, w: 640, h: 480)]
    for target in targets {
        placer.move(pad.id, to: target)
        print("asked: \(pixels(target)) placed: \(placer.frame(pad.id).map(pixels) ?? "gone")")
    }
    let d = WinWindows.hwnd(pad.id).flatMap(WinWindows.insets) ?? Insets()
    print("delta: \(Int(d.left)) \(Int(d.top)) \(Int(d.right)) \(Int(d.bottom))",
          "elevated \(placer.elevated.contains(pad.id))")
    return 0
}

// probeMoor pins the front Notepad to the left top slot in a fresh choices file with slot stacks
// off, so a second Notepad is kept in the channel, runs the pass loop for the given seconds, and
// prints each move and release with its time, then the final frames.
func probeMoor(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("moor: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }) else {
        print("moor: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    var choices = Choices(slots: [.leftTop: pad.bundle], widths: Widths(left: 40, right: 30),
                          paused: opts.paused)
    choices.slotStacks = false
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
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }) else {
        print("tray: no window of \(opts.app)")
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
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
          let hwnd = WinWindows.hwnd(pad.id) else {
        print("hotkeys: no window of \(opts.app)")
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
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }) else {
        print("skip: no window of \(opts.app)")
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

// probeLift pins the front Notepad to the left top slot, lets the loop place it, then runs Maximize
// on it twice, the way Ctrl+Alt+Enter does, and prints its frame after each.
func probeLift(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("lift: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
          let hwnd = WinWindows.hwnd(pad.id) else {
        print("lift: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices(slots: [.leftTop: pad.bundle], widths: Widths(left: 40, right: 30)))
    } catch {
        print("lift: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let frame = { app.windows.frame(pad.id).map(pixels) ?? "gone" }
    app.run(until: App.now + 1.5)
    print("placed: \(frame())")
    _ = bringForward(hwnd)
    print("foreground: \(foreground()) notepad \(hex(pad.id))")
    print("lift ran: \(app.actions.run("maximize")) lifted \(app.anchors.isLifted(pad.id))")
    app.run(until: App.now + 1.5)
    print("lifted: \(frame())")
    print("lower ran: \(app.actions.run("maximize")) lifted \(app.anchors.isLifted(pad.id))")
    app.run(until: App.now + 1.5)
    print("lowered: \(frame())")
    let use = app.anchors.inUse(wide)
    print("strip: \(pixels(Geometry.regions(wide, use.left, use.right).left))")
    print("over: \(pixels(Geometry.lift(wide, .left, use.left, use.right)))")
    return 0
}

// probeLogin chooses Launch at login once through the tray's command and prints whether the Run key
// now holds Moorings and the command it holds.
func probeLogin(_: ProbeOptions) -> Int32 {
    let tray = Tray(app: App(store: Store()))
    print("before: \(LoginItem.enabled)")
    tray.perform(.atLogin)
    print("after: \(LoginItem.enabled)")
    print("executable: \(LoginItem.executable)")
    return 0
}

// probeQuit adds the tray icon and runs the loop for two seconds to show it does not end by itself,
// then chooses Quit through the tray's command, runs the loop again with five seconds to spare, and
// prints how long each run took and whether the icon is gone after the tray hides.
func probeQuit(_: ProbeOptions) -> Int32 {
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("quit: \(error)")
        return 1
    }
    let app = App(store: store)
    let tray = Tray(app: app)
    print("added: \(tray.show())")
    var t = App.now
    app.run(until: t + 2)
    print("ran without quit: \(stamp(App.now - t)) s")
    tray.perform(.quit)
    t = App.now
    app.run(until: t + 5)
    print("ran after quit: \(stamp(App.now - t)) s")
    let window = tray.window
    tray.hide()
    print("icon gone: \(window.map(Tray.iconGone) ?? false)")
    return 0
}

// standClass is the window class of the stand probe's window.
let standClass = "MooringsStandIn"

// probeStand shows a captioned window that accepts any size for the given seconds, then closes. Windows
// caps a window that leaves its size limits to the default at the desktop plus its border, 1044 by 788
// on the runner, so Notepad cannot take a 3440x1440 slot there. This window answers WM_GETMINMAXINFO
// with no cap, as every window on a real ultrawide is capped past its size, and stands in for the
// app under the fake ultrawide.
func probeStand(_ opts: ProbeOptions) -> Int32 {
    let instance = GetModuleHandleW(nil)
    var wc = WNDCLASSEXW()
    wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
    wc.hInstance = instance
    wc.lpfnWndProc = { hwnd, msg, wParam, lParam in
        switch msg {
        case UINT(WM_GETMINMAXINFO):
            if let info = UnsafeMutablePointer<MINMAXINFO>(bitPattern: Int(lParam)) {
                info.pointee.ptMaxTrackSize = POINT(x: 32000, y: 32000)
                info.pointee.ptMaxSize = POINT(x: 32000, y: 32000)
            }
            return 0
        case UINT(WM_DESTROY):
            PostQuitMessage(0)
            return 0
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
    }
    let name = wide(standClass)
    let registered = name.withUnsafeBufferPointer { buffer in
        wc.lpszClassName = buffer.baseAddress
        return RegisterClassExW(&wc) != 0
    }
    guard registered else {
        print("stand: class not registered: \(GetLastError())")
        return 1
    }
    // 0x00CF0000 is WS_OVERLAPPEDWINDOW and 0x10000000 is WS_VISIBLE.
    let style: DWORD = 0x00CF_0000 | 0x1000_0000
    guard let hwnd = CreateWindowExW(0, name, wide("Moorings stand-in"), style, 100, 100, 600, 400, nil, nil,
                                     instance, nil) else {
        print("stand: no window: \(GetLastError())")
        return 1
    }
    print("stand: \(hex(WinWindows.id(hwnd))) pid \(GetCurrentProcessId())")
    pump(until: App.now + opts.seconds)
    if IsWindow(hwnd) {
        _ = DestroyWindow(hwnd)
    }
    return 0
}

// dragTarget is where the drag probe lets go: the left edge, below the corner zones.
let dragTarget = (x: Int32(2), y: Int32(400))

// probeDrag runs the pass loop with a fresh choices file while another thread presses on the front
// Notepad's caption with SendInput, drags it to the left edge in 20 steps and lets go, with Alt held
// through the drop for --alt. It prints the drop, Notepad's frame, the channel, the left top holder
// and how often the hook was put back.
func probeDrag(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("drag: no ultrawide")
        return 1
    }
    let windows = WinWindows.scan(screens: screens).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
          let hwnd = WinWindows.hwnd(pad.id) else {
        print("drag: no window of \(opts.app)")
        return 1
    }
    let store = Store()
    do {
        try store.save(Choices())
    } catch {
        print("drag: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    app.hooksMouse = !opts.noHook
    app.drag.dropped = { id, drop in
        let on = switch drop {
        case let .zone(name): "zone \(name)"
        case let .park(key): "park \(key)"
        case .none: "nothing"
        }
        print("dropped \(hex(id)) on \(on) at \(stamp(App.now))")
    }
    _ = bringForward(hwnd)
    print("before: \(pixels(pad.frame))")
    var full: WindowsBool = false
    _ = SystemParametersInfoW(UINT(SPI_GETDRAGFULLWINDOWS), 0, &full, 0)
    print("drag full windows: \(full.boolValue)")
    let from = (x: Int32((pad.frame.x + pad.frame.w / 2).rounded()), y: Int32(pad.frame.y + 15))
    let alt = opts.alt
    Thread {
        Sleep(1000)
        dragInput(from: from, to: dragTarget, alt: alt)
    }.start()
    app.run(until: App.now + opts.seconds)
    print("hook delivered: \(WinMouseHook.delivered)")
    print("hook reinstalled: \(app.mouse.reinstalls)")
    print("footprint: \(app.footprint.last.map(pixels) ?? "never") shows \(app.footprint.shows)",
          "hidden \(app.footprint.shown == nil)")
    print("after: \(app.windows.frame(pad.id).map(pixels) ?? "gone")")
    print("channel: \(pixels(app.anchors.channel(wide)))")
    print("left top: \(app.anchors.choices.slots[.leftTop] ?? "")")
    return 0
}

// probeFootprint brings the front Notepad forward, shows the footprint over it at the given frame,
// or inside Notepad, and prints its rect, its style bits and the foreground window after the show
// and after a click on the footprint's middle.
func probeFootprint(_ opts: ProbeOptions) -> Int32 {
    let windows = WinWindows.scan(screens: .current(minAspect: opts.minAspect)).windows
    guard let pad = windows.first(where: { $0.bundle.hasSuffix(opts.app) }),
          let hwnd = WinWindows.hwnd(pad.id) else {
        print("footprint: no window of \(opts.app)")
        return 1
    }
    _ = bringForward(hwnd)
    pump(until: App.now + 0.3)
    print("foreground before: \(foreground()) notepad \(hex(pad.id))")
    let f = opts.frame ?? Frame(x: pad.frame.x + 50, y: pad.frame.y + 50, w: 300, h: 200)
    let footprint = WinFootprint()
    footprint.activates = opts.activate
    footprint.show(f, style: FootprintStyle())
    pump(until: App.now + 0.5)
    guard let window = footprint.window else {
        print("footprint: no window: \(GetLastError())")
        return 1
    }
    var r = RECT()
    _ = GetWindowRect(window, &r)
    print("rect: \(pixels(Frame(r)))")
    let ex = DWORD(truncatingIfNeeded: GetWindowLongPtrW(window, GWL_EXSTYLE))
    let bit = { (b: DWORD) in ex & b == b }
    print("exstyle: transparent \(bit(WinFootprint.transparent)) noactivate \(bit(WinFootprint.noActivate))",
          "layered \(bit(WinFootprint.layered)) topmost \(bit(WinFootprint.topmost))",
          "toolwindow \(bit(WinFootprint.toolWindow))")
    print("visible: \(IsWindowVisible(window))")
    print("foreground after show: \(foreground())")
    let mid = (x: Int32((f.x + f.w / 2).rounded()), y: Int32((f.y + f.h / 2).rounded()))
    sendMouse(mid.x, mid.y, 0)
    pump(until: App.now + 0.1)
    sendMouse(mid.x, mid.y, 0x0002)
    sendMouse(mid.x, mid.y, 0x0004)
    pump(until: App.now + 0.5)
    print("foreground after click: \(foreground()) footprint \(hex(WinWindows.id(window)))")
    footprint.hide()
    pump(until: App.now + 0.3)
    print("visible after hide: \(IsWindowVisible(window))")
    return 0
}

// dragInput presses the left button at from, moves to to in 20 steps 15 ms apart and lets go, the
// way a hand drags a window by its caption. With alt, Alt goes down before the press and up half a
// second after the release.
func dragInput(from: (x: Int32, y: Int32), to: (x: Int32, y: Int32), alt: Bool) {
    if alt {
        sendKey(0x12, up: false)
    }
    sendMouse(from.x, from.y, 0)
    Sleep(100)
    sendMouse(from.x, from.y, 0x0002)
    Sleep(100)
    for i in 1...20 {
        let x = from.x + (to.x - from.x) * Int32(i) / 20, y = from.y + (to.y - from.y) * Int32(i) / 20
        sendMouse(x, y, 0)
        Sleep(15)
    }
    Sleep(200)
    sendMouse(to.x, to.y, 0x0004)
    if alt {
        Sleep(500)
        sendKey(0x12, up: true)
    }
}

// sendMouse moves the pointer to x, y on the virtual desktop with SendInput, adding the button
// flags, 0x0002 for down and 0x0004 for up.
func sendMouse(_ x: Int32, _ y: Int32, _ buttons: DWORD) {
    let left = GetSystemMetrics(SM_XVIRTUALSCREEN), top = GetSystemMetrics(SM_YVIRTUALSCREEN)
    let w = max(2, GetSystemMetrics(SM_CXVIRTUALSCREEN)), h = max(2, GetSystemMetrics(SM_CYVIRTUALSCREEN))
    var input = INPUT()
    input.type = DWORD(INPUT_MOUSE)
    input.mi.dx = LONG((Int(x - left) * 65535) / Int(w - 1))
    input.mi.dy = LONG((Int(y - top) * 65535) / Int(h - 1))
    input.mi.dwFlags = 0x0001 | 0x8000 | 0x4000 | buttons
    _ = SendInput(1, &input, Int32(MemoryLayout<INPUT>.size))
}

// sendKey sends one key down or up with SendInput.
func sendKey(_ vk: WORD, up: Bool) {
    var input = INPUT()
    input.type = DWORD(INPUT_KEYBOARD)
    input.ki.wVk = vk
    input.ki.dwFlags = up ? 0x0002 : 0
    _ = SendInput(1, &input, Int32(MemoryLayout<INPUT>.size))
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
    // taskbar is the height a sized monitor keeps for the taskbar, the Windows 11 default at 100
    // percent.
    static let taskbar = 48.0
    // fake stands in for every attached monitor when set, as --screen sets it.
    nonisolated(unsafe) static var fake: Monitor?

    // full is rcMonitor, the whole display.
    var full: Frame
    // usable is rcWork, the display without the taskbar.
    var usable: Frame
    // primary is true for the display that holds the origin.
    var primary: Bool

    // sized returns one primary monitor at the origin of size, with the taskbar along its bottom.
    static func sized(_ size: Size) -> Monitor {
        let full = Frame(x: 0, y: 0, w: Double(size.w), h: Double(size.h))
        let usable = Frame(x: 0, y: 0, w: full.w, h: max(1, full.h - taskbar))
        return Monitor(full: full, usable: usable, primary: true)
    }

    // all returns every monitor in EnumDisplayMonitors order, or the fake one alone when set.
    static func all() -> [Monitor] {
        if let fake {
            return [fake]
        }
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

// probeContracts runs the engine's contract suites on the Win32 adapters, against stand-in windows
// this exe opens with the stand probe, and prints each rule broken and the count.
func probeContracts(_ opts: ProbeOptions) -> Int32 {
    let host = WinHost(minAspect: opts.minAspect)
    let windows = WinWindows()
    let scheduler = WinScheduler()
    host.timers = { scheduler.fire($0) }
    let banner = BannerWindow(minAspect: opts.minAspect)
    var failures = WindowStoreContract.run(windows, host: host)
    failures += OverlayContract.run(WinFootprint(), store: windows, host: host)
    failures += NotifierContract.run(WinNotifier { banner.show($0, $1) }, store: windows, host: host)
    failures += SchedulerContract.run(scheduler, clock: WinClock(), host: host)
    for f in failures {
        print("contract failed: \(f)")
    }
    print("contracts: 4 suites, \(failures.count) failures")
    return failures.isEmpty ? 0 : 1
}

// WinHost is the Windows ContractHost: each window is a stand-in from this exe's stand probe in a
// process of its own, found by its process id, and waiting pumps this thread's messages.
final class WinHost: ContractHost {
    // timers runs a thread timer's work and reports whether the timer was its.
    var timers: (UINT_PTR) -> Bool = { _ in false }
    // minAspect is the ratio a monitor needs to count as ultrawide.
    private let minAspect: Double
    // stands lists the stand-in processes the host started.
    private var stands: [Process] = []

    // init builds a host whose screens count a monitor at least minAspect wide as ultrawide.
    init(minAspect: Double) {
        self.minAspect = minAspect
    }

    // minimum is the smallest window Windows lets a person size, which the stand-in keeps.
    var minimum: (w: Double, h: Double)? {
        (Double(GetSystemMetrics(SM_CXMINTRACK)), Double(GetSystemMetrics(SM_CYMINTRACK)))
    }

    // now is the tick count in seconds.
    var now: Double { App.now }

    // screens reads the monitors.
    func screens() -> Screens {
        Screens.current(minAspect: minAspect)
    }

    // open starts a stand-in process and returns its window once it shows.
    func open() -> WindowID? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Tray.executable)
        p.arguments = ["--probe", "stand", "--seconds", "120"]
        do {
            try p.run()
        } catch {
            print("contracts: stand-in did not start: \(error)")
            return nil
        }
        stands.append(p)
        let pid = DWORD(p.processIdentifier)
        var found: HWND?
        _ = wait(until: now + 5) {
            found = WinWindows.topLevel().first {
                WinWindows.processID($0) == pid && WinWindows.className($0) == standClass && IsWindowVisible($0)
            }
            return found != nil
        }
        return found.map(WinWindows.id)
    }

    // openRefusing is nil: a window that refuses every move needs an elevated process.
    func openRefusing() -> WindowID? {
        nil
    }

    // wait pumps this thread's messages, handing its thread timers to timers, until done or the
    // deadline.
    func wait(until deadline: Double, _ done: () -> Bool) -> Bool {
        var msg = MSG()
        while !done() {
            guard now < deadline else { return false }
            while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                if msg.message == UINT(WM_TIMER), msg.hwnd == nil, timers(msg.wParam) {
                    continue
                }
                _ = TranslateMessage(&msg)
                _ = DispatchMessageW(&msg)
            }
            Sleep(5)
        }
        return true
    }

    // finish ends every stand-in process.
    func finish() {
        for p in stands where p.isRunning {
            p.terminate()
        }
        stands = []
    }
}
