import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// App runs the engine on the main thread's message loop: it builds the Windows adapters and one
// Engine on them, and pumps the messages its timers, hooks and shortcuts arrive by.
final class App {
    // windows reads and moves the windows.
    let windows = WinWindows()
    // pointer reads and warps the mouse pointer.
    let pointer = WinPointer()
    // apps names and opens programs.
    let apps = WinApps()
    // log writes the engine's lines to stderr.
    let log = WinLog()
    // timers hands each engine object its own thread timer, which the message loop fires.
    let timers = WinTimers()
    // store holds the choices file.
    let store: Store
    // minAspect is the ratio a monitor needs to count as ultrawide. Only probes change it.
    let minAspect: Double
    // notify shows a banner with a title and a body. It does nothing until the app wires the
    // banner, so probes print none.
    var notify: (String, String) -> Void = { _, _ in }
    // hotkeys delivers the shortcuts bound for the actions.
    private(set) lazy var hotkeys = WinHotkeys { [unowned self] name in self.engine.actions.run(name) }
    // keys spells the shortcuts and grabs the keys a hold takes.
    private(set) lazy var keys = WinKeys(hotkeys)
    // mouse delivers the pointer for drag snapping.
    private(set) lazy var mouse = WinMouseHook()
    // drag feeds a window moved by its frame to the engine's drag follower.
    private(set) lazy var drag = WinDrag(app: self)
    // footprint shows where a dragged window will land.
    let footprint = WinFootprint()
    // screens reads the attached monitors.
    private(set) lazy var screens = WinScreens(minAspect: minAspect)
    // events delivers the window events and hands a move or size by a window's frame to the drag.
    private(set) lazy var events: WinEvents = {
        let e = WinEvents(screens: screens)
        e.dragBegan = { [unowned self] in drag.began($0) }
        e.dragEnded = { [unowned self] in drag.ended() }
        return e
    }()
    // engine builds and runs every engine object on the Windows platform, with none of the routed
    // actions yet.
    private(set) lazy var engine: Engine = {
        let e = Engine(platform: platform, features: [])
        e.passes.tellsRefused = true
        return e
    }()
    // platform is what the engine reads and drives on Windows.
    private(set) lazy var platform = Platform(
        windows: windows, screens: screens, overlay: footprint,
        notifier: WinNotifier { [unowned self] in self.notify($0, $1) }, clock: WinClock(), store: store,
        pointer: pointer, keys: keys, apps: apps, log: log, timers: timers, events: events, grid: WinNoGrid(),
        badge: WinNoBadge()
    )
    // hooksMouse is false only in the drag probe's negative control, which runs without the hook.
    var hooksMouse = true

    // init builds the app on store, whose choices the engine loads.
    init(store: Store, minAspect: Double = Layout.minAspect) {
        self.store = store
        self.minAspect = minAspect
    }

    // now is the time in seconds since the system started, the same clock in every process.
    static var now: Double { Double(GetTickCount64()) / 1000 }

    // run watches window events, pumps messages and runs passes until until, or until WM_QUIT when
    // until is nil.
    func run(until: Double? = nil) {
        let stop = until.map { SetTimer(nil, 0, Self.millis($0 - Self.now), nil) } ?? 0
        engine.listen()
        if hooksMouse {
            mouse.handler = { [unowned self] message, p in
                if message == UINT(WM_MOUSEMOVE) {
                    self.drag.pointer(p)
                }
            }
            mouse.start()
        }
        defer {
            mouse.stop()
            events.stop()
            if stop != 0 {
                _ = KillTimer(nil, stop)
            }
            engine.passes.stop()
        }
        engine.wake()
        var msg = MSG()
        while GetMessageW(&msg, nil, 0, 0) {
            if mouse.deliver(msg) {
                continue
            }
            if msg.message == UINT(WM_HOTKEY), msg.hwnd == nil {
                hotkeys.fire(msg.wParam)
                continue
            }
            if msg.message == UINT(WM_TIMER), msg.hwnd == nil {
                switch msg.wParam {
                case stop where stop != 0:
                    return
                default:
                    if !timers.fire(msg.wParam) {
                        _ = mouse.tick(msg.wParam)
                    }
                }
                continue
            }
            _ = TranslateMessage(&msg)
            _ = DispatchMessageW(&msg)
        }
    }

    // millis converts seconds to a timer interval of at least 1 ms.
    private static func millis(_ seconds: Double) -> UINT {
        UINT(max(1, (seconds * 1000).rounded(.up)))
    }

}

// WinClock is the Windows Clock: seconds since the system started, the clock App.now reads.
final class WinClock: Clock {
    // now is the tick count in seconds.
    var now: Double { App.now }
}

// WinNoGrid is the grid view of a platform with no grid action yet: it never shows and takes no clicks.
final class WinNoGrid: GridView {
    // onMouse is never told anything.
    var onMouse: ((GridMouse, Point) -> Void)?
    // shown is always nil.
    var shown: GridMark? { nil }

    // show paints nothing.
    func show(_ grid: OverlayGrid, in area: Frame, gap: Double, style: FootprintStyle, palette: Palette) {}

    // hide does nothing.
    func hide() {}

    // contains is always false.
    func contains(_ p: Point) -> Bool {
        false
    }
}

// WinNoBadge is the badge view of a platform with no stack badge yet: it never shows.
final class WinNoBadge: BadgeView {
    // shown is always nil.
    var shown: BadgeMark? { nil }

    // show paints nothing.
    func show(_ count: Int, at front: Frame, palette: Palette) {}

    // hide does nothing.
    func hide() {}
}

// WinScheduler is the Windows Scheduler: one thread timer, its work run from the message loop's
// WM_TIMER branch through fire.
final class WinScheduler: Scheduler {
    // timer is the pending thread timer's id, 0 when none.
    private(set) var timer: UINT_PTR = 0
    // work is the pending work, nil when nothing is pending.
    private var work: (() -> Void)?

    // schedule runs work at time at, replacing any pending work.
    func schedule(at: Double, _ work: @escaping () -> Void) {
        cancel()
        self.work = work
        timer = SetTimer(nil, 0, UINT(max(1, ((at - App.now) * 1000).rounded(.up))), nil)
    }

    // cancel drops the pending work and its timer.
    func cancel() {
        if timer != 0 {
            _ = KillTimer(nil, timer)
        }
        timer = 0
        work = nil
    }

    // fire runs the pending work when id is its timer, clearing it first so the work may schedule
    // more, and reports whether id was its timer.
    func fire(_ id: UINT_PTR) -> Bool {
        guard id != 0, id == timer else { return false }
        let w = work
        cancel()
        w?()
        return true
    }
}
