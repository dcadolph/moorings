import MooringsCore

// PassContext is what a platform adds to a pass beyond the windows.
public struct PassContext: Sendable {
    // waiting reports whether an observer the platform set is still waiting on an app, which reads
    // every app and keeps the passes coming.
    public var waiting: Bool
    // launching is when the passes stop looking for the first window of an app that just launched.
    public var launching: Double

    // init builds a context; the defaults wait on nothing.
    public init(waiting: Bool = false, launching: Double = -Double.infinity) {
        self.waiting = waiting
        self.launching = launching
    }
}

// PassLoop runs the passes: each reads the windows, asks Anchors where they belong, moves them,
// reads them back, tells the owner about released pins and refused windows, and sets the next pass
// through the platform's Scheduler. Passes run every Pace.pollSeconds while windows change, and
// stop once three reads in a row find nothing new until an event wakes them.
public final class PassLoop {
    // context returns the platform's part of the next pass.
    public var context: () -> PassContext = { PassContext() }
    // mouseHeld reports whether the owner holds the mouse button, which leaves dragged pins alone.
    public var mouseHeld: () -> Bool = { false }
    // deadlines lists the times the platform needs a pass at beyond the anchors' own.
    public var deadlines: () -> [Double] = { [] }
    // ticked runs before each pass the timer starts, so the platform can catch a change of grant.
    public var ticked: () -> Void = {}
    // prepare runs before each pass the store is ready for.
    public var prepare: () -> Void = {}
    // refreshed is told the windows still alive when the passes prune what is gone.
    public var refreshed: (Set<WindowID>) -> Void = { _ in }
    // after is told each pass's scan, screens and whether the mouse was held.
    public var after: (Scan, Screens, Bool) -> Void = { _, _, _ in }
    // firstPass runs once, after the first pass.
    public var firstPass: () -> Void = {}
    // paced runs after each pass set the next one.
    public var paced: () -> Void = {}
    // exitFullScreen takes a window out of native fullscreen where the platform has one.
    public var exitFullScreen: (WindowID) -> Void = { _ in }
    // appName returns the name to show for a bundle.
    public var appName: (String) -> String = { $0 }
    // spell writes a shortcut the way the platform's keyboard does.
    public var spell: (Shortcut) -> String = { $0.spelled }
    // greenButton reports whether a released pin goes back with a click on its green button.
    public var greenButton = false
    // tellsRefused reports whether a refused window gets a banner: on Windows a refusal means the
    // window runs as administrator.
    public var tellsRefused = false
    // moved is told each move a pass applied, the time and where the window read back, when set.
    public var moved: ((Move, Double, Frame?) -> Void)?
    // released is told each pin the owner moved by hand, and the time.
    public var released: (WindowID, Double) -> Void = { _, _ in }
    // passed is told the time of each pass and how many moves it made.
    public var passed: (Double, Int) -> Void = { _, _ in }
    // log writes what a pass could not do.
    public var log: (String) -> Void = { _ in }

    // lastRead lists the ids the last pass read, front to back.
    public private(set) var lastRead: [WindowID] = []
    // still reports whether the last pass read what the one before read and moved nothing.
    public private(set) var still = false
    // due is when the next pass runs, nil when none is set.
    public private(set) var due: Double?

    // platform reads and moves the windows and keeps the time.
    private let platform: Platform
    // anchors decides where each window belongs.
    private let anchors: Anchors
    // lastFrames lists the frames the last pass read, in the order of lastRead.
    private var lastFrames: [Frame] = []
    // woke is when the last wake came.
    private var woke = -Double.infinity
    // lastApps is when dead windows were last pruned, nil before the first time.
    private var lastApps: Double?
    // started reports whether the first pass ran.
    private var started = false
    // toldRefused reports whether the banner told of a refused window this session.
    private var toldRefused = false

    // init builds the passes on platform and anchors.
    public init(platform: Platform, anchors: Anchors) {
        self.platform = platform
        self.anchors = anchors
    }

    // wake marks windows as changing, so passes run every Pace.pollSeconds until they settle.
    public func wake() {
        let t = platform.clock.now
        woke = t
        if let due, due <= t + Pace.pollSeconds {
            return
        }
        schedule(t + Pace.pollSeconds)
    }

    // landed records frame as the last frame read for the window with id, which an action just read
    // back after moving it, so the pass after reads it at rest and ends the polling.
    public func landed(_ id: WindowID, at frame: Frame) {
        if let i = lastRead.firstIndex(of: id) {
            lastFrames[i] = frame
        }
    }

    // stop clears the pending pass.
    public func stop() {
        schedule(nil)
    }

    // moor runs one pass, applies its moves, and sets the next pass.
    public func moor() {
        still = false
        defer { pace() }
        guard platform.windows.ready else { return }
        prepare()
        let screens = platform.screens.current()
        let t = platform.clock.now
        let ctx = context()
        if PassPlan.refreshesApps(now: t, last: lastApps, waiting: ctx.waiting) {
            lastApps = t
            let alive = platform.windows.alive()
            anchors.prune(alive: alive)
            refreshed(alive)
        } else if anchors.hasCastOff || !anchors.stashed.isEmpty {
            anchors.prune(alive: platform.windows.alive())
        }
        let forced = !started || ctx.waiting || t < ctx.launching
        let scan = platform.windows.scan(screens, full: forced)
        let refused = platform.windows.refused
        let list = scan.windows.filter { !refused.contains($0.id) }
        let held = mouseHeld()
        let scene = Scene(
            screen: screens.wide, windows: list, focused: scan.focused?.id, mouseHeld: held,
            now: platform.clock.now)
        let moves = anchors.moor(scene)
        for move in moves {
            apply(move, bundle: list.first { $0.id == move.id }?.bundle ?? "?")
        }
        let read = list.map(\.id), frames = list.map(\.frame)
        still = moves.isEmpty && !held && read == lastRead && frames == lastFrames
        lastRead = read
        lastFrames = frames
        after(Scan(windows: list, focused: scan.focused), screens, held)
        for id in anchors.justReleased {
            tellReleased(id, list)
        }
        tellRefused(scan.windows)
        passed(t, moves.count)
        if !started {
            started = true
            firstPass()
        }
    }

    // apply carries out one move: it takes a window out of native fullscreen, or moves it, reads
    // where it landed, and moves it once more when it kept a larger size than it was given. A window
    // that refused the move is not tried again.
    private func apply(_ move: Move, bundle: String) {
        if move.exitFullScreen {
            exitFullScreen(move.id)
            return
        }
        let w = platform.windows
        w.move(move.id, to: move.frame, from: nil, behavior: anchors.choices.behavior)
        let got = w.frame(move.id)
        moved?(move, platform.clock.now, got)
        guard !w.refused.contains(move.id) else { return }
        guard let got else {
            log("window \(move.id) \(bundle): move to \(move.frame) unreadable")
            anchors.unread(move)
            return
        }
        guard let again = anchors.landed(move, got: got) else {
            if !Actions.near(got, move.frame, tolerance: Anchors.tolerance) {
                log("window \(move.id) \(bundle): move to \(move.frame) refused, landed at \(got)")
            }
            return
        }
        log("window \(move.id) read back at \(Int(got.w))x\(Int(got.h)) after a move: holding that size for now")
        w.move(again.id, to: again.frame, from: nil, behavior: anchors.choices.behavior)
        if let moved {
            moved(again, platform.clock.now, w.frame(again.id))
        }
    }

    // tellReleased logs a pin the owner moved by hand and shows the banner that says how to put it
    // back, naming the restore shortcut when one is bound.
    private func tellReleased(_ id: WindowID, _ list: [WindowInfo]) {
        let w = list.first { $0.id == id }
        let now = w.map { "\($0.frame)" } ?? "?"
        let back = anchors.readBack(id).map { "\($0)" } ?? "?"
        let asked = anchors.target(id).map { "\($0)" } ?? "?"
        log("window \(id) was moved by hand: released at \(now), read back \(back), asked \(asked)")
        released(id, platform.clock.now)
        let name = w.map { appName($0.bundle) } ?? "The window"
        platform.notifier.notify(
            "\(name) released",
            Self.releasedBody(
                key: Bindings(anchors.choices).map["restore"].map(spell), greenButton: greenButton))
    }

    // releasedBody is the banner body for a released pin: the green button where there is one, and
    // the restore shortcut when key names it.
    public static func releasedBody(key: String?, greenButton: Bool) -> String {
        if greenButton {
            return "Click its green button to put it back\(key.map { ",\nor press \($0)" } ?? "")."
        }
        return key.map { "Press \($0) on it to put it back." } ?? "Moorings leaves it where you put it."
    }

    // tellRefused shows the banner once a session for the first window that refused a move, when the
    // platform tells of refusals.
    private func tellRefused(_ all: [WindowInfo]) {
        let refused = platform.windows.refused
        guard tellsRefused, !toldRefused, let w = all.first(where: { refused.contains($0.id) }) else { return }
        toldRefused = true
        platform.notifier.notify(
            "\(appName(w.bundle)) runs as administrator",
            "Moorings cannot move it. Run Moorings as administrator to hold it too.")
    }

    // pace sets the next pass: soon while windows change, every Pace.busySeconds while something
    // pending sends no event, at the next deadline, or not at all.
    private func pace() {
        let t = platform.clock.now
        let ctx = context()
        let busy = !platform.windows.ready || ctx.waiting || t < ctx.launching
        schedule(Pace.next(now: t, woke: woke, busy: busy, deadlines: anchors.deadlines() + deadlines(), still: still))
        paced()
    }

    // schedule sets the next pass at time at, or clears it when at is nil.
    private func schedule(_ at: Double?) {
        due = at
        guard let at else {
            platform.scheduler.cancel()
            return
        }
        platform.scheduler.schedule(at: at) { [weak self] in
            guard let self else { return }
            due = nil
            ticked()
            moor()
        }
    }
}
