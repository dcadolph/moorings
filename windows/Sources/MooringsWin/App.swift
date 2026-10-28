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
    // actions runs the window actions the shortcuts name.
    private(set) lazy var actions = WinActions(app: self)
    // hotkeys delivers the shortcuts bound for the actions.
    private(set) lazy var hotkeys = WinHotkeys { [unowned self] name in self.actions.run(name) }
    // mouse delivers the pointer for drag snapping.
    private(set) lazy var mouse = WinMouseHook()
    // drag follows a window moved by its frame and runs its drop.
    private(set) lazy var drag = WinDrag(app: self)
    // footprint shows where a dragged window will land.
    let footprint = WinFootprint()
    // scheduler runs the engine's deferred work from the message loop's timer branch.
    let scheduler = WinScheduler()
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
    // timer is the pending pass timer's id, 0 when none.
    private var timer: UINT_PTR = 0
    // due is when the pending pass runs, nil when none is set.
    private var due: Double?
    // woke is when the last window event arrived.
    private var woke = -Double.infinity
    // still reports whether the last pass read what the one before read and moved nothing.
    private var still = false
    // lastRead lists the ids the last pass read, in order.
    private var lastRead: [WindowID] = []
    // lastFrames lists the frames the last pass read, in the order of lastRead.
    private var lastFrames: [Frame] = []
    // lastApps is when dead windows were last pruned, nil before the first time.
    private var lastApps: Double?
    // toldElevated reports whether the banner has told of a window running as administrator this
    // session.
    private var toldElevated = false

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

    // wake marks windows as changing, so passes run every Pace.pollSeconds until they settle.
    func wake() {
        woke = Self.now
        poll()
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
        if kind.geometry, !lastRead.contains(id) {
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
            for id in [stop, timer] where id != 0 {
                _ = KillTimer(nil, id)
            }
            timer = 0
            scheduler.cancel()
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
                case timer where timer != 0:
                    _ = KillTimer(nil, timer)
                    timer = 0
                    due = nil
                    moor()
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

    // poll runs passes every Pace.pollSeconds from now until windows settle.
    private func poll() {
        let t = Self.now
        woke = t
        if let due, due <= t + Pace.pollSeconds {
            return
        }
        schedule(t + Pace.pollSeconds)
    }

    // schedule sets the timer for the next pass at time at, or clears it when at is nil.
    private func schedule(_ at: Double?) {
        if timer != 0 {
            _ = KillTimer(nil, timer)
            timer = 0
        }
        due = at
        guard let at else { return }
        timer = SetTimer(nil, 0, Self.millis(at - Self.now), nil)
    }

    // millis converts seconds to a timer interval of at least 1 ms.
    private static func millis(_ seconds: Double) -> UINT {
        UINT(max(1, (seconds * 1000).rounded(.up)))
    }

    // moor runs one pass, applies its moves, and sets the timer for the next.
    func moor() {
        let t = Self.now
        let screens = Screens.current(minAspect: minAspect)
        self.screens = screens
        if PassPlan.refreshesApps(now: t, last: lastApps, waiting: false) {
            lastApps = t
            anchors.prune(alive: Set(WinWindows.topLevel().map(WinWindows.id)))
        }
        let (all, focused) = WinWindows.scan(screens: screens)
        let list = all.filter { !windows.elevated.contains($0.id) }
        let mouseHeld = dragging || GetAsyncKeyState(VK_LBUTTON) < 0
        let scene = Scene(screen: screens.wide, windows: list, focused: focused?.id,
                          mouseHeld: mouseHeld, now: t)
        let moves = anchors.moor(scene)
        for move in moves {
            apply(move)
        }
        for id in anchors.justReleased {
            released(id, t)
            tellReleased(id, list)
        }
        tellElevated(all)
        passed(t, moves.count)
        let read = list.map(\.id), frames = list.map(\.frame)
        still = moves.isEmpty && !mouseHeld && read == lastRead && frames == lastFrames
        lastRead = read
        lastFrames = frames
        schedule(Pace.next(now: Self.now, woke: woke, busy: false, deadlines: anchors.deadlines(),
                           still: still))
    }

    // landed records frame as the last frame read for the window with id, which an action just
    // read back after moving it, so the pass after reads it at rest and ends the polling.
    func landed(_ id: WindowID, at frame: Frame) {
        if let i = lastRead.firstIndex(of: id) {
            lastFrames[i] = frame
        }
    }

    // tellReleased shows the banner for a pin the owner moved by hand, naming the shortcut that
    // puts it back when one is bound.
    private func tellReleased(_ id: WindowID, _ list: [WindowInfo]) {
        let name = list.first { $0.id == id }.map { Tray.appName($0.bundle) } ?? "The window"
        let how = Bindings(anchors.choices).map["restore"].map {
            "Press \(WinHotkeys.spelled($0)) on it to put it back."
        }
        notify("\(name) released", how ?? "Moorings leaves it where you put it.")
    }

    // tellElevated shows the banner once a session for the first window that refused a move because
    // it runs as administrator.
    private func tellElevated(_ all: [WindowInfo]) {
        guard !toldElevated, let w = all.first(where: { windows.elevated.contains($0.id) }) else {
            return
        }
        toldElevated = true
        notify("\(Tray.appName(w.bundle)) runs as administrator",
               "Moorings cannot move it. Run Moorings as administrator to hold it too.")
    }

    // apply carries out one move: it moves the window, reads where it landed, and moves it once
    // more when it kept a larger size than it was given. A window that refused the move as elevated
    // is not tried again. Windows has no native fullscreen to leave, so a request to leave it does
    // nothing.
    private func apply(_ move: Move) {
        guard !move.exitFullScreen else { return }
        windows.move(move.id, to: move.frame)
        let got = windows.frame(move.id)
        moved(move, Self.now, got)
        guard !windows.elevated.contains(move.id) else { return }
        guard let got else {
            anchors.unread(move)
            return
        }
        guard let again = anchors.landed(move, got: got) else { return }
        windows.move(again.id, to: again.frame)
        moved(again, Self.now, windows.frame(again.id))
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
