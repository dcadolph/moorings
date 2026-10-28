import MooringsCore

// HoverMover moves or resizes the window under the pointer while the hover modifiers are held and no
// button is down. It reads the pointer on ticks only while they are held, so it costs nothing at
// rest, and it leaves pinned, fullscreen, stashed windows and file panels alone. The platform reports
// modifier flags in the CGEventFlags layout the core reads.
public final class HoverMover {
    // tickSeconds is how often the pointer is read while the modifiers are held.
    public static let tickSeconds = 1.0 / 60

    // pointer returns where the pointer is in top-left coordinates and whether a mouse button is held.
    public var pointer: () -> (Point, Bool) = { (Point(x: 0, y: 0), false) }
    // hit returns the window under a point, nil when there is none.
    public var hit: (Point) -> WindowID? = { _ in nil }
    // shortcutsOn reports whether the shortcuts are on, since a hover is one.
    public var shortcutsOn: () -> Bool = { true }
    // wake runs after a hover that held a window ends, so the passes look at where it landed.
    public var wake: () -> Void = {}
    // log is told why a hover did nothing.
    public var log: (String) -> Void = { _ in }

    // platform reads and moves the windows and reads the clock.
    private let platform: Platform
    // anchors holds the choices, the pins and the stashed windows.
    private let anchors: Anchors
    // ticker reads the pointer while the modifiers are held, a scheduler of its own.
    private let ticker: any Scheduler
    // mode is what the held modifiers do, nil while none are held.
    private var mode: HoverMode?
    // origin is where the pointer was when the modifiers went down, in top-left coordinates.
    private var origin = Point(x: 0, y: 0)
    // target is the window being moved, nil until it is read after the modifiers go down.
    private var target: WindowID?
    // start is the target's frame when the modifiers went down.
    private var start = Frame(x: 0, y: 0, w: 0, h: 0)
    // corner is the corner that follows the pointer in a resize.
    private var corner = HoverCorner.bottomRight
    // last is the pointer offset last applied, so a still pointer writes nothing.
    private var last: Point?

    // init builds a hover mover on platform and anchors that reads the pointer through ticker.
    public init(platform: Platform, anchors: Anchors, ticker: any Scheduler) {
        self.platform = platform
        self.anchors = anchors
        self.ticker = ticker
    }

    // active reports whether a hover holds a window, so the layout treats it as a window being dragged.
    public var active: Bool { target != nil }

    // flagsChanged starts, switches or ends a hover as the held modifiers change. It may run inside
    // the platform's event callback, so it reads no window.
    public func flagsChanged(_ flags: UInt64, at p: Point) {
        let choices = anchors.choices
        let next = choices.overlay.trigger.held(flags) ? nil : Hover.mode(flags, choices.overlay)
        guard next != mode else { return }
        end()
        if let next {
            begin(next, at: p)
        }
    }

    // begin starts a hover of mode at p and reads the window under p on the first tick.
    private func begin(_ mode: HoverMode, at p: Point) {
        if let why = Hold.blocker(anchors, ready: platform.windows.ready, shortcutsOn: shortcutsOn(),
                                  buttonDown: pointer().1) {
            log("hover: keys held but \(why): nothing moves")
            return
        }
        self.mode = mode
        origin = p
        ticker.schedule(at: platform.clock.now) { [weak self] in self?.read(mode) }
    }

    // read takes the free window under where the modifiers went down for a hover of mode, then starts
    // the ticks.
    private func read(_ mode: HoverMode) {
        guard self.mode == mode, target == nil else { return }
        let id = hit(origin)
        guard let w = platform.windows.scan(platform.screens.current(), full: true).windows
            .first(where: { $0.id == id && !$0.isFilePanel }),
            !anchors.pinned(w), !w.isFullScreen, !anchors.stashed.contains(w.id)
        else {
            log("hover: no free window under the pointer")
            return
        }
        anchors.save(w)
        target = w.id
        start = w.frame
        corner = Hover.corner(w.frame, nearest: origin)
        last = nil
        tick()
    }

    // end stops a hover and lets the layout look at where the window landed.
    private func end() {
        let moved = target != nil
        ticker.cancel()
        mode = nil
        target = nil
        if moved {
            wake()
        }
    }

    // tick moves the target by how far the pointer has gone since the modifiers went down, then
    // schedules the next tick. Nothing moves while a button is down.
    private func tick() {
        guard let mode, let id = target else { return }
        ticker.schedule(at: platform.clock.now + Self.tickSeconds) { [weak self] in self?.tick() }
        let (loc, down) = pointer()
        guard !down else { return }
        let d = Point(x: (loc.x - origin.x).rounded(), y: (loc.y - origin.y).rounded())
        guard d != last else { return }
        last = d
        let f = Hover.frame(mode, start: start, corner: corner, dx: d.x, dy: d.y)
        if mode == .move {
            platform.windows.position(id, x: f.x, y: f.y)
            return
        }
        platform.windows.move(id, to: f, from: nil, behavior: anchors.choices.behavior)
        if let got = platform.windows.frame(id), got.w != f.w || got.h != f.h {
            let kept = Hover.keep(f, corner: corner, w: got.w, h: got.h)
            platform.windows.position(id, x: kept.x, y: kept.y)
        }
    }
}
