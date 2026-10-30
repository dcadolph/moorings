import MooringsCore

// PassLoop runs the passes: each reads the windows, asks Anchors where they belong, moves them,
// reads them back, tells the owner about released pins and refused windows, and sets the next pass
// through the platform's Scheduler. Passes run every Pace.pollSeconds while windows change, and
// stop once three reads in a row find nothing new until an event wakes them.
public final class PassLoop {
    // greenButton reports whether a released pin goes back with a click on its green button.
    public var greenButton = false
    // tellsRefused reports whether a refused window gets a banner: on Windows a refusal means the
    // window runs as administrator.
    public var tellsRefused = false

    // lastRead lists the ids the last pass read, front to back.
    public private(set) var lastRead: [WindowID] = []
    // still reports whether the last pass read what the one before read and moved nothing.
    public private(set) var still = false
    // due is when the next pass runs, nil when none is set.
    public private(set) var due: Double?
    // fullWoke is when the last wake came that named no window, so the scans read every app until
    // the windows settle.
    public private(set) var fullWoke = -Double.infinity
    // launching is when the passes stop looking for the first window of an app that just launched.
    public var launching = -Double.infinity

    // engine is the orchestration this object calls: wake, moor, save, landed.
    unowned let engine: Engine
    // platform reads and moves the windows and keeps the time.
    private let platform: Platform
    // scheduler sets the next pass, a scheduler of the passes' own.
    private let scheduler: any Scheduler
    // anchors decides where each window belongs.
    private let anchors: Anchors
    // workspaces names the windows a recall waits for and the times its placed windows are due a
    // second look.
    private let workspaces: WorkspaceKeeper
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

    // init builds the passes on engine's platform and anchors, waiting on workspaces' recalls.
    public init(engine: Engine, platform: Platform, anchors: Anchors, workspaces: WorkspaceKeeper) {
        self.engine = engine
        self.platform = platform
        self.anchors = anchors
        self.workspaces = workspaces
        scheduler = platform.timers.scheduler()
    }

    // wake marks windows as changing, so passes run every Pace.pollSeconds until they settle. A full
    // wake also makes the scans read every app for Pace.settleSeconds; an event that named its window
    // wakes narrow, since the source marked that window's app. Nothing wakes while paused.
    public func wake(full: Bool = true) {
        guard !anchors.choices.paused else { return }
        let t = platform.clock.now
        woke = t
        if full {
            fullWoke = t
        }
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
        engine.beforePass()
        guard platform.windows.ready else { return }
        let screens = platform.screens.current()
        let t = platform.clock.now
        let waiting = platform.events.waiting || workspaces.waiting
        if PassPlan.refreshesApps(now: t, last: lastApps, waiting: waiting) {
            lastApps = t
            let alive = platform.windows.alive()
            anchors.prune(alive: alive)
            engine.prune(alive: alive)
        } else if anchors.hasCastOff || !anchors.stashed.isEmpty {
            anchors.prune(alive: platform.windows.alive())
        }
        let forced = !started || waiting || t < launching || t - fullWoke < Pace.settleSeconds
        let scan = platform.windows.scan(screens, full: forced)
        let refused = platform.windows.refused
        let list = scan.windows.filter { !refused.contains($0.id) }
        let held = engine.mouseHeld
        let scene = Scene(
            screen: screens.wide, windows: list, focused: scan.focused?.id, mouseHeld: held,
            now: platform.clock.now)
        let moves = anchors.moor(scene)
        platform.log.trace(.passes, "pass \(forced ? "full" : "apps") read \(list.count) moved \(moves.count)")
        for move in moves {
            apply(move, bundle: list.first { $0.id == move.id }?.bundle ?? "?")
        }
        let read = list.map(\.id), frames = list.map(\.frame)
        still = moves.isEmpty && !held && read == lastRead && frames == lastFrames
        lastRead = read
        lastFrames = frames
        let kept = Scan(windows: list, focused: scan.focused)
        engine.passed(kept, screens, held)
        platform.events.watch(kept)
        for id in anchors.justReleased {
            tellReleased(id, list)
        }
        tellRefused(scan.windows)
        engine.observers.passed(t, moves.count)
        if !started {
            started = true
            openAnchored()
        }
    }

    // openAnchored opens every anchored app that is not running, in the background, after the first
    // pass, and logs an app the platform could not start.
    private func openAnchored() {
        for bundle in anchors.opening() where !platform.apps.open(bundle, background: true, target: nil) {
            log("could not open anchored app \(bundle)")
        }
    }

    // log writes what a pass could not do.
    private func log(_ line: String) {
        platform.log.note(.passes, line)
    }

    // apply carries out one move: it takes a window out of native fullscreen, or moves it, reads
    // where it landed, and moves it once more when it kept a larger size than it was given. A window
    // that refused the move is not tried again.
    private func apply(_ move: Move, bundle: String) {
        if move.exitFullScreen {
            platform.windows.exitFullScreen(move.id)
            return
        }
        let w = platform.windows
        w.move(move.id, to: move.frame, from: nil, behavior: anchors.choices.behavior)
        let got = w.frame(move.id)
        engine.observers.moved?(move, platform.clock.now, got)
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
        if let moved = engine.observers.moved {
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
        engine.observers.released(id, platform.clock.now)
        let name = w.map { platform.apps.name($0.bundle) } ?? "The window"
        platform.notifier.notify(
            "\(name) released",
            Self.releasedBody(
                key: Bindings(anchors.choices).map["restore"].map(platform.keys.spell), greenButton: greenButton))
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
            "\(platform.apps.name(w.bundle)) runs as administrator",
            "Moorings cannot move it. Run Moorings as administrator to hold it too.")
    }

    // pace sets the next pass: soon while windows change, every Pace.busySeconds while something
    // pending sends no event, at the next deadline, or not at all, and never while paused.
    private func pace() {
        guard !anchors.choices.paused else {
            schedule(nil)
            return
        }
        let t = platform.clock.now
        let busy = !platform.windows.ready || platform.events.waiting || workspaces.waiting || t < launching
        schedule(
            Pace.next(
                now: t, woke: woke, busy: busy, deadlines: anchors.deadlines() + workspaces.deadlines(),
                still: still))
    }

    // schedule sets the next pass at time at, or clears it when at is nil.
    private func schedule(_ at: Double?) {
        due = at
        guard let at else {
            scheduler.cancel()
            return
        }
        scheduler.schedule(at: at) { [weak self] in
            guard let self else { return }
            due = nil
            moor()
        }
    }
}
