import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// probeSoak pins the open Notepad to the left top slot and the open Edge to the right top slot in a
// fresh choices file, runs the app's loop once for --minutes, and from a scheduler reads both pins
// every minute and every two minutes from minute 2 perturbs once in turn: a nudge the pass must
// release and the Restore path must put back, a minimize and restore of the Notepad pin, and a
// second Notepad that must land in the channel. It prints one line per minute and exits 1 on the
// first failure. Under --paused it pauses through the engine once the minute 1 frames are read.
// Under --leak it opens handles every minute and never closes them, so the bounds must trip.
func probeSoak(_ opts: ProbeOptions) -> Int32 {
    let screens = Screens.current(minAspect: opts.minAspect)
    guard let wide = screens.wide else {
        print("soak: no ultrawide")
        return 1
    }
    let open = WinWindows.scan(screens: screens).windows
    guard let pad = open.first(where: { $0.bundle.hasSuffix(Soak.notepad) }),
        let edge = open.first(where: { $0.bundle.hasSuffix(Soak.edge) })
    else {
        print("soak: needs a Notepad and an Edge window open")
        return 1
    }
    let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "moorings-soak-\(UUID().uuidString).json")
    defer {
        try? FileManager.default.removeItem(at: file)
        try? FileManager.default.removeItem(at: Store(url: file).aside)
    }
    let store = Store(url: file)
    var choices = Choices(
        slots: [.leftTop: pad.bundle, .rightTop: edge.bundle], widths: Widths(left: 40, right: 30), paused: false)
    choices.slotStacks = false
    do {
        try store.save(choices)
    } catch {
        print("soak: \(error)")
        return 1
    }
    let app = App(store: store, minAspect: opts.minAspect)
    let soak = Soak(
        app: app, wide: wide, pins: [pad.id, edge.id], minutes: opts.minutes, pausing: opts.paused,
        leaking: opts.leak)
    print("soak: start, Notepad \(hex(pad.id)) left top, Edge \(hex(edge.id)) right top, \(opts.minutes) minutes")
    soak.begin()
    app.run(until: App.now + Double(opts.minutes) * 60 + 5)
    print("soak: \(soak.failed ? "failed" : "held") after \(soak.minute) minutes, \(soak.nudges) nudges")
    return soak.failed ? 1 : 0
}

// Soak holds a soak's pins, its schedules and what it has measured, all on the loop thread.
final class Soak {
    // notepad is the end of Notepad's image path.
    static let notepad = "\\notepad.exe"
    // edge is the end of Edge's image path.
    static let edge = "\\msedge.exe"
    // nudge is how far a nudge moves a pin right and down.
    static let nudge = 40.0
    // releaseSeconds is how soon the pass must release a nudged pin.
    static let releaseSeconds = 1.0
    // backSeconds is how soon a pin must be back after the Restore path, or a second Notepad in the
    // channel after it opens.
    static let backSeconds = 2.0
    // leakPerMinute is how many handles a leaking soak opens each minute.
    static let leakPerMinute = 60

    // app runs the loop and the engine.
    let app: App
    // wide is the ultrawide's usable frame.
    let wide: Frame
    // pins holds the Notepad pin, then the Edge pin.
    let pins: [WindowID]
    // minutes is how long the soak runs.
    let minutes: Int
    // pausing pauses the engine once the minute 1 frames are read, the negative control.
    let pausing: Bool
    // leaking opens leakPerMinute handles every minute and never closes them, the bounds' negative
    // control.
    let leaking: Bool
    // ticks runs the per-minute read.
    private let ticks: WinScheduler
    // steps runs the waits inside a perturbation.
    private let steps: WinScheduler
    // start is when the soak began.
    private var start = 0.0
    // home holds each pin's frame at minute 1.
    private var home: [WindowID: Frame] = [:]
    // released holds the pins the engine released since the last nudge.
    private var released: Set<WindowID> = []
    // hooks is the hook's reinstall count at the start.
    private var hooks = 0
    // minute is the last minute read.
    private(set) var minute = 0
    // nudges counts the nudges made.
    private(set) var nudges = 0
    // failed is true once a line failed.
    private(set) var failed = false

    // init builds a soak of pins on wide.
    init(app: App, wide: Frame, pins: [WindowID], minutes: Int, pausing: Bool, leaking: Bool) {
        self.app = app
        self.wide = wide
        self.pins = pins
        self.minutes = minutes
        self.pausing = pausing
        self.leaking = leaking
        ticks = app.timers.make()
        steps = app.timers.make()
    }

    // begin hears the engine's releases and schedules the first read a minute out.
    func begin() {
        start = App.now
        hooks = app.mouse.reinstalls
        app.engine.observers.released = { [unowned self] id, _ in released.insert(id) }
        ticks.schedule(at: start + 60) { [unowned self] in tick() }
    }

    // tick reads the pins and the counters, prints the minute's line, and starts the minute's
    // perturbation.
    private func tick() {
        guard !failed else { return }
        minute += 1
        if minute == 1 && !baseline() {
            return
        }
        if leaking {
            leak()
        }
        let held = pins.filter(holds).count
        let now = Counters.read()
        let reinstalls = app.mouse.reinstalls - hooks
        print(
            "soak \(minute): pins held \(held)/\(pins.count), private \(now.privateMB) MB, handles \(now.handles),",
            "gdi \(now.gdi), hook reinstalled \(reinstalls)")
        guard held == pins.count else {
            fail("soak \(minute): pins not held: \(pins.map(show).joined(separator: ", "))")
            return
        }
        guard reinstalls == 0 else {
            fail("soak \(minute): hook reinstalled \(reinstalls)")
            return
        }
        if minute < minutes {
            ticks.schedule(at: start + Double(minute + 1) * 60) { [unowned self] in tick() }
        }
        guard minute >= 2, minute % 2 == 0 else { return }
        switch (minute / 2 - 1) % 3 {
        case 0: nudge()
        case 1: minimize()
        default: openSecond()
        }
    }

    // leak opens leakPerMinute unnamed events and drops them, so the process keeps every handle.
    private func leak() {
        for _ in 0..<Self.leakPerMinute {
            _ = CreateEventW(nil, false, false, nil)
        }
    }

    // baseline records the minute 1 frames, which must sit on the strips, and pauses the engine under
    // the negative control. It reports whether the frames were on their strips.
    private func baseline() -> Bool {
        let use = app.engine.anchors.inUse(wide)
        let strips = Geometry.regions(wide, use.left, use.right)
        for (id, strip) in zip(pins, [strips.left, strips.right]) {
            guard let f = app.windows.frame(id), Actions.near(f, strip, tolerance: 1) else {
                fail("soak 1: pin \(hex(id)) off its strip: strip \(pixels(strip)) at \(show(id))")
                return false
            }
            home[id] = f
        }
        if pausing {
            app.engine.anchors.choices.paused = true
            app.engine.save()
            print("soak 1: paused through the engine")
        }
        return true
    }

    // nudge moves a pin, Notepad and Edge in turn, the nudge distance right and down, expects the
    // engine to release it, then puts it back the way the Restore action does and expects it home.
    private func nudge() {
        let id = pins[nudges % pins.count]
        nudges += 1
        guard let f = app.windows.frame(id) else {
            fail("soak \(minute): pin \(hex(id)) not back: released false at gone")
            return
        }
        released.remove(id)
        app.windows.move(id, to: Frame(x: f.x + Self.nudge, y: f.y + Self.nudge, w: f.w, h: f.h))
        steps.schedule(at: App.now + Self.releaseSeconds) { [unowned self] in
            guard released.contains(id) else {
                fail("soak \(minute): pin \(hex(id)) not back: released false at \(show(id))")
                return
            }
            app.engine.anchors.remoor(id)
            app.engine.wake()
            app.engine.moor()
            steps.schedule(at: App.now + Self.backSeconds) { [unowned self] in
                if !holds(id) {
                    fail("soak \(minute): pin \(hex(id)) not back: released true at \(show(id))")
                }
            }
        }
    }

    // minimize minimizes the Notepad pin and restores it a second later; the next read checks it is
    // home.
    private func minimize() {
        guard let hwnd = WinWindows.hwnd(pins[0]) else {
            fail("soak \(minute): pin \(hex(pins[0])) gone before the minimize")
            return
        }
        _ = ShowWindow(hwnd, SW_MINIMIZE)
        steps.schedule(at: App.now + 1) {
            _ = ShowWindow(hwnd, SW_RESTORE)
        }
    }

    // openSecond opens a second Notepad, expects it inside the channel, and closes it; the next read
    // checks both pins are home.
    private func openSecond() {
        let before = Set(WinWindows.topLevel())
        let verb = MooringsWin.wide("open")
        let file = MooringsWin.wide("notepad.exe")
        let result = ShellExecuteW(nil, verb, file, nil, nil, SW_SHOWNORMAL)
        guard Int(bitPattern: result) > 32 else {
            fail("soak \(minute): second Notepad not in the channel: not started, \(Int(bitPattern: result))")
            return
        }
        steps.schedule(at: App.now + Self.backSeconds) { [unowned self] in
            let screens = Screens.current(minAspect: app.minAspect)
            let second = WinWindows.topLevel().first {
                !before.contains($0)
                    && WinWindows.image(WinWindows.processID($0))?.lowercased().hasSuffix(Self.notepad) == true
                    && WinWindows.describe($0, screens: screens) != nil
            }
            guard let second else {
                fail("soak \(minute): second Notepad not in the channel: no window")
                return
            }
            let channel = app.engine.anchors.channel(wide)
            let f = app.windows.frame(WinWindows.id(second))
            _ = PostMessageW(second, UINT(WM_CLOSE), 0, 0)
            guard let f, Self.inside(f, channel) else {
                fail(
                    "soak \(minute): second Notepad not in the channel: channel \(pixels(channel))",
                    "at \(f.map(pixels) ?? "gone")")
                return
            }
        }
    }

    // holds reports whether pin id reads back within 1 pixel of its minute 1 frame.
    private func holds(_ id: WindowID) -> Bool {
        guard let f = app.windows.frame(id), let h = home[id] else { return false }
        return Actions.near(f, h, tolerance: 1)
    }

    // show writes pin id's frame now, or gone.
    private func show(_ id: WindowID) -> String {
        app.windows.frame(id).map(pixels) ?? "gone"
    }

    // fail prints the failed line and ends the loop.
    private func fail(_ parts: String...) {
        print(parts.joined(separator: " "))
        failed = true
        ticks.cancel()
        steps.cancel()
        PostQuitMessage(0)
    }

    // inside reports whether f lies within area, 1 pixel either way.
    static func inside(_ f: Frame, _ area: Frame) -> Bool {
        f.x >= area.x - 1 && f.y >= area.y - 1 && f.x + f.w <= area.x + area.w + 1 && f.y + f.h <= area.y + area.h + 1
    }
}

// Counters is what the soak bounds in its own process: private bytes, kernel handles and GDI
// objects.
struct Counters {
    // privateMB is the private bytes in whole megabytes.
    var privateMB: Int
    // handles is the open kernel handles.
    var handles: DWORD
    // gdi is the GDI objects.
    var gdi: DWORD

    // GetMemory is K32GetProcessMemoryInfo's shape, loaded from kernel32 at run time.
    typealias GetMemory = @convention(c) (HANDLE?, UnsafeMutableRawPointer?, DWORD) -> Int32

    // read reads the counters now. PrivateUsage is the last field of a PROCESS_MEMORY_COUNTERS_EX laid
    // out by hand: two DWORDs and nine SIZE_Ts, 80 bytes on x64. A failed read gives 0.
    static func read() -> Counters {
        let process = GetCurrentProcess()
        var words = [UInt64](repeating: 0, count: 10)
        let size = DWORD(words.count * MemoryLayout<UInt64>.size)
        words.withUnsafeMutableBytes { $0.storeBytes(of: size, toByteOffset: 0, as: DWORD.self) }
        if let kernel = GetModuleHandleW(wide("kernel32.dll")),
            let proc = GetProcAddress(kernel, "K32GetProcessMemoryInfo")
        {
            let get = unsafeBitCast(proc, to: GetMemory.self)
            if words.withUnsafeMutableBytes({ get(process, $0.baseAddress, size) }) == 0 {
                words[9] = 0
            }
        }
        var handles: DWORD = 0
        _ = GetProcessHandleCount(process, &handles)
        let gdi = GetGuiResources(process, DWORD(GR_GDIOBJECTS))
        return Counters(privateMB: Int(words[9] / (1 << 20)), handles: handles, gdi: gdi)
    }
}
