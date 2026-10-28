import MooringsCore

// Stasher parks windows at a screen edge with a sliver left on screen. Resting the pointer on the
// sliver slides the window out, and moving the pointer off it slides the window back. A click in a
// slid-out window, the stash action again, or unstash-all ends the stash. The platform reports the
// pointer through moved only while watching says a window is stashed, from its own pointer events,
// so a still pointer costs nothing, and the adapter puts stashed windows back when it quits.
public final class Stasher {
    // restMargin is how long in seconds past the rest time the rest check runs, so it lands after it.
    public static let restMargin = 0.01
    // edgeReach is how close in points to a screen edge a Command-drag must end to stash there.
    public static let edgeReach = 2.0

    // Entry is one stashed window and the area it parks in.
    public struct Entry: Equatable, Sendable {
        // s is the stash.
        public var s: Stashed
        // area is the usable area the window parks at the edge of.
        public var area: Frame
    }

    // pointer returns where the pointer is in top-left coordinates and whether a mouse button is held.
    public var pointer: () -> (Point, Bool) = { (Point(x: 0, y: 0), false) }
    // watching is told true when the first window is stashed, so the platform starts calling moved on
    // pointer events, and false when the last stash ends.
    public var watching: (Bool) -> Void = { _ in }
    // wake runs after a stash or unstash, so the passes look again.
    public var wake: () -> Void = {}
    // log is told why a stash did nothing.
    public var log: (String) -> Void = { _ in }

    // platform reads and moves the windows and reads the screens.
    private let platform: Platform
    // anchors holds the choices, the slots and the set of stashed windows the passes leave alone.
    private let anchors: Anchors
    // rest runs the rest check, a scheduler of its own so it never replaces the passes' work.
    private let rest: any Scheduler
    // entries lists the stashed windows.
    public private(set) var entries: [Entry] = []
    // watched reports whether watching was last told true.
    private var watched = false

    // init builds a stasher on platform and anchors that checks a resting pointer through rest.
    public init(platform: Platform, anchors: Anchors, rest: any Scheduler) {
        self.platform = platform
        self.anchors = anchors
        self.rest = rest
    }

    // run applies a stash action: stash toggles the focused window, unstash-all puts every stashed
    // window back.
    @discardableResult
    public func run(_ name: String) -> Bool {
        if name == "unstash-all" {
            let any = !entries.isEmpty
            unstashAll()
            return any
        }
        guard let w = platform.windows.scan(platform.screens.current(), full: false).focused else {
            log("stash: no focused window")
            return false
        }
        if entries.contains(where: { $0.s.id == w.id }) {
            unstash(w.id)
            return true
        }
        return stash(w, edge: nil)
    }

    // stash parks w at edge, or at the nearest edge that can take it when nil, and reports whether it
    // parked. Unstashing puts it back at original, or where it is now when nil. An edge another
    // display touches cannot take it, and on the ultrawide neither can a side with an anchored app,
    // so a stash never covers a strip. A move the platform refuses is undone.
    @discardableResult
    public func stash(_ w: WindowInfo, edge: StashEdge?, original: Frame? = nil) -> Bool {
        guard !anchors.choices.paused, !anchors.pinned(w), !w.isFullScreen else {
            log("stash: pinned and fullscreen windows are not stashed")
            return false
        }
        let screens = platform.screens.current()
        guard let i = screens.index(w.frame) else { return false }
        let area = screens.usable[i]
        var blocked: Set<StashEdge> = []
        var span: Frame?
        if i == screens.ultrawide {
            let sides = Set(anchors.choices.slots.keys.map(\.side))
            if sides.contains(.left) {
                blocked.insert(.left)
            }
            if sides.contains(.right) {
                blocked.insert(.right)
            }
            span = anchors.channel(area)
        }
        let others = screens.full.indices.filter { $0 != i }.map { screens.full[$0] }
        var allowed = Stash.edges(screens.full[i], others: others, blocked: blocked)
        if let edge {
            allowed = allowed.intersection([edge])
        }
        guard var s = Stash.stash(w.id, w.frame, area: area, allowed: allowed, span: span) else {
            log("stash: no free edge on this display")
            return false
        }
        anchors.stashed.insert(w.id)
        platform.windows.move(w.id, to: s.hidden, from: nil, behavior: anchors.choices.behavior)
        guard let landed = platform.windows.frame(w.id), Stash.parked(landed, screen: area) else {
            anchors.stashed.remove(w.id)
            platform.windows.move(w.id, to: w.frame, from: nil, behavior: anchors.choices.behavior)
            log("stash: the window stayed on screen")
            return false
        }
        s.hidden = landed
        if let original {
            s.original = original
        }
        entries.removeAll { $0.s.id == w.id }
        entries.append(Entry(s: s, area: area))
        if !watched {
            watched = true
            watching(true)
        }
        wake()
        return true
    }

    // unstash puts the window with id back where it was before the stash.
    public func unstash(_ id: WindowID) {
        guard let e = entries.first(where: { $0.s.id == id }) else { return }
        forget(id)
        platform.windows.move(id, to: e.s.original, from: nil, behavior: anchors.choices.behavior)
        wake()
    }

    // unstashAll puts every stashed window back where it was.
    public func unstashAll() {
        for e in entries {
            unstash(e.s.id)
        }
    }

    // prune ends the stash of every window not in alive, the windows that still exist.
    public func prune(alive: Set<WindowID>) {
        for e in entries where !alive.contains(e.s.id) {
            forget(e.s.id)
        }
    }

    // forget ends the stash of the window with id without moving it.
    private func forget(_ id: WindowID) {
        entries.removeAll { $0.s.id == id }
        anchors.stashed.remove(id)
        if entries.isEmpty, watched {
            watched = false
            rest.cancel()
            watching(false)
        }
    }

    // clicked ends the stash of a slid-out window under p, leaving it where it is. It reads only the
    // frames already known, so a platform may call it inside its event callback.
    public func clicked(_ p: Point) {
        for e in entries where e.s.out {
            let f = e.s.shown
            if p.x >= f.x, p.x <= f.x + f.w, p.y >= f.y, p.y <= f.y + f.h {
                forget(e.s.id)
            }
        }
    }

    // dropEdge returns the edge a drag ending at p with the held keys stashes at: command held,
    // command not one of the keys snapping needs, and p within edgeReach of a display's left, right
    // or bottom edge.
    public func dropEdge(_ p: Point, held: Set<String>) -> StashEdge? {
        guard held.contains("command"), !anchors.choices.snapping.snapModifiers.contains("command") else {
            return nil
        }
        let screens = platform.screens.current()
        guard
            let f = screens.full.first(where: { p.x >= $0.x && p.x < $0.x + $0.w && p.y >= $0.y && p.y < $0.y + $0.h })
        else { return nil }
        if p.x - f.x <= Self.edgeReach {
            return .left
        }
        if f.x + f.w - 1 - p.x <= Self.edgeReach {
            return .right
        }
        if f.y + f.h - 1 - p.y <= Self.edgeReach {
            return .bottom
        }
        return nil
    }

    // moved slides a stashed window out or back as the pointer asks. The platform calls it on each
    // pointer move and button release while watching. A window that has moved since it was parked or
    // slid out was taken by the owner, so its stash ends where it is.
    public func moved() {
        guard !anchors.choices.paused else { return }
        let (p, held) = pointer()
        let now = platform.clock.now
        for i in entries.indices.reversed() {
            var e = entries[i]
            let ask = Stash.hover(&e.s, p, screen: e.area, now: now, mouseHeld: held)
            entries[i] = e
            switch ask {
            case .none:
                continue
            case .slideOut:
                guard let f = platform.windows.frame(e.s.id), Actions.near(f, e.s.hidden, tolerance: Actions.tolerance)
                else {
                    forget(e.s.id)
                    continue
                }
                entries[i].s.out = true
                entries[i].s.restSince = nil
                platform.windows.move(e.s.id, to: e.s.shown, from: f, behavior: anchors.choices.behavior)
                platform.windows.raise(e.s.id)
            case .slideBack:
                guard let f = platform.windows.frame(e.s.id), Actions.near(f, e.s.shown, tolerance: Actions.tolerance)
                else {
                    forget(e.s.id)
                    continue
                }
                entries[i].s.out = false
                platform.windows.move(e.s.id, to: e.s.hidden, from: f, behavior: anchors.choices.behavior)
            }
        }
        scheduleRest(now: now)
    }

    // scheduleRest checks the pointer again when the earliest parked window resting under it has
    // rested for Stash.restSeconds, since a still pointer sends no events.
    private func scheduleRest(now: Double) {
        rest.cancel()
        let due = entries.compactMap { e in e.s.out || !e.s.armed ? nil : e.s.restSince }.min()
        guard let due else { return }
        rest.schedule(at: max(now, due + Stash.restSeconds + Self.restMargin)) { [weak self] in
            self?.moved()
        }
    }
}
