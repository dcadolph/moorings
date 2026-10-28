import Foundation
import WinSDK

import MooringsCore
import MooringsEngine

// App runs the passes on the main thread's message loop: each pass reads the windows, asks Anchors
// where they belong, and moves them, on a one-shot timer Pace sets.
final class App {
    // anchors decides where each window belongs.
    let anchors: Anchors
    // windows reads and moves the windows.
    let windows = WinWindows()
    // store holds the choices file.
    let store: Store
    // minAspect is the ratio a monitor needs to count as ultrawide. Only probes change it.
    let minAspect: Double
    // moved is told each move a pass applied, the time, and where the window read back.
    var moved: (Move, Double, Frame?) -> Void = { _, _, _ in }
    // released is told each pin the owner moved by hand, and the time.
    var released: (WindowID, Double) -> Void = { _, _ in }
    // noticed is told each window event that wakes the passes, the window, and the time.
    var noticed: (WinEvent, WindowID, Double) -> Void = { _, _, _ in }
    // passed is told the time of each pass and how many moves it made.
    var passed: (Double, Int) -> Void = { _, _ in }
    // notify shows a banner with a title and a body. It does nothing until the app wires the
    // banner, so probes print none.
    var notify: (String, String) -> Void = { _, _ in }
    // reloaded is told after the choices were re-read from the file, so the app can rebind the
    // shortcuts.
    var reloaded: () -> Void = {}
    // reloads counts the times the choices were re-read because the file changed or was asked for.
    private(set) var reloads = 0
    // actions runs the window actions the shortcuts name.
    private(set) lazy var actions: ActionRunner = {
        let r = ActionRunner(platform: platform, anchors: anchors)
        r.landed = { [unowned self] id, frame in
            landed(id, at: frame)
            wake()
        }
        r.wake = { [unowned self] in wake() }
        r.moor = { [unowned self] in moor() }
        r.log = { line in FileHandle.standardError.write(Data("actions: \(line)\n".utf8)) }
        return r
    }()
    // hotkeys delivers the shortcuts bound for the actions.
    private(set) lazy var hotkeys = WinHotkeys { [unowned self] name in self.actions.run(name) }
    // mouse delivers the pointer for drag snapping.
    private(set) lazy var mouse = WinMouseHook()
    // drag feeds a window moved by its frame to the follower.
    private(set) lazy var drag = WinDrag(app: self)
    // follower follows a dragged window, shows where it will land, and runs its drop.
    private(set) lazy var follower: DragFollower = {
        let f = DragFollower(platform: platform, anchors: anchors, preview: { [unowned self] name, w, screens, _ in
            actions.preview(name, for: w, screens: screens)
        }, apply: { [unowned self] name, w, screens, _ in
            actions.apply(name, to: w, screens: screens)
        })
        f.appName = { Tray.appName($0) }
        f.changed = { [unowned self] in
            save()
            wake()
        }
        return f
    }()
    // footprint shows where a dragged window will land.
    let footprint = WinFootprint()
    // scheduler runs the engine's deferred work from the message loop's timer branch.
    let scheduler = WinScheduler()
    // passes run the window passes on the engine's pass loop.
    private(set) lazy var passes: PassLoop = {
        let p = PassLoop(platform: platform, anchors: anchors)
        p.prepare = { [unowned self] in
            if store.changed() {
                reload()
            }
        }
        p.mouseHeld = { [unowned self] in dragging || GetAsyncKeyState(VK_LBUTTON) < 0 }
        p.refreshed = { [unowned self] alive in actions.prune(alive: alive) }
        p.after = { [unowned self] _, screens, _ in self.screens = screens }
        p.appName = { Tray.appName($0) }
        p.spell = { WinHotkeys.spelled($0) }
        p.tellsRefused = true
        p.moved = { [unowned self] move, t, got in moved(move, t, got) }
        p.released = { [unowned self] id, t in released(id, t) }
        p.passed = { [unowned self] t, n in passed(t, n) }
        p.log = { line in FileHandle.standardError.write(Data("passes: \(line)\n".utf8)) }
        return p
    }()
    // platform is what the engine reads and drives on Windows.
    private(set) lazy var platform = Platform(
        windows: windows, screens: WinScreens(minAspect: minAspect), overlay: footprint,
        notifier: WinNotifier { [unowned self] in self.notify($0, $1) }, clock: WinClock(), scheduler: scheduler,
        store: store, warpCursor: { p in _ = SetCursorPos(Int32(p.x.rounded()), Int32(p.y.rounded())) }
    )
    // hooksMouse is false only in the drag probe's negative control, which runs without the hook.
    var hooksMouse = true
    // watcher delivers the window events.
    private(set) lazy var watcher = WinWatcher { [unowned self] kind, hwnd in self.event(kind, hwnd) }
    // dragging reports whether the owner is moving or sizing a window by its frame.
    private var dragging = false
    // screens are the displays the last pass read.
    private var screens: Screens?

    // init loads the choices from store.
    init(store: Store, minAspect: Double = Layout.minAspect) {
        self.store = store
        self.minAspect = minAspect
        anchors = Anchors(choices: store.load())
    }

    // now is the time in seconds since the system started, the same clock in every process.
    static var now: Double { Double(GetTickCount64()) / 1000 }

    // save writes the choices, telling stderr when the file cannot be written.
    func save() {
        do {
            try store.save(anchors.choices)
        } catch {
            FileHandle.standardError.write(Data("choices not saved: \(error)\n".utf8))
        }
    }

    // reload re-reads the choices from the file and tells reloaded.
    func reload() {
        anchors.choices = store.load()
        reloads += 1
        reloaded()
    }

    // wake marks windows as changing, so passes run every Pace.pollSeconds until they settle.
    func wake() {
        passes.wake()
    }

    // event wakes the passes for a window event a pass acts on. A move or birth of a window no scan
    // keeps changes nothing a pass decides, so it is dropped. Moving or sizing a window by its frame
    // counts as the mouse button held until it ends.
    private func event(_ kind: WinEvent, _ hwnd: HWND) {
        switch kind {
        case .moveSizeStart:
            dragging = true
            drag.began(hwnd)
        case .moveSizeEnd:
            dragging = false
            drag.ended()
        default:
            break
        }
        let id = WinWindows.id(hwnd)
        if kind.geometry, !passes.lastRead.contains(id) {
            let screens = screens ?? Screens.current(minAspect: minAspect)
            guard WinWindows.describe(hwnd, screens: screens) != nil else { return }
        }
        noticed(kind, id, Self.now)
        wake()
    }

    // run watches window events, pumps messages and runs passes until until, or until WM_QUIT when
    // until is nil.
    func run(until: Double? = nil) {
        let stop = until.map { SetTimer(nil, 0, Self.millis($0 - Self.now), nil) } ?? 0
        watcher.start()
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
            watcher.stop()
            if stop != 0 {
                _ = KillTimer(nil, stop)
            }
            passes.stop()
        }
        wake()
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
                    if !scheduler.fire(msg.wParam) {
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

    // moor runs one pass now.
    func moor() {
        passes.moor()
    }

    // landed records frame as the last frame read for the window with id, which an action just read
    // back after moving it, so the pass after reads it at rest and ends the polling.
    func landed(_ id: WindowID, at frame: Frame) {
        passes.landed(id, at: frame)
    }
}

// WinClock is the Windows Clock: seconds since the system started, the clock App.now reads.
final class WinClock: Clock {
    // now is the tick count in seconds.
    var now: Double { App.now }
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
