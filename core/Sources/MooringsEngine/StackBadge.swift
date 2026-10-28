import MooringsCore

// StackBadge counts the windows stacked under a resting pointer and shows the count on the stack's
// front window, so a person sees how many windows cycle-stacked-windows steps through.
public final class StackBadge {
    // restMove is the most in points the pointer may move between two ticks and still count as
    // resting.
    public static let restMove = 2.0

    // engine is the orchestration this object calls: wake, moor, save, landed.
    unowned let engine: Engine
    // platform reads the pointer and the windows and paints the badge.
    private let platform: Platform
    // anchors holds the stacking choices and the gap.
    private let anchors: Anchors
    // ticker runs the ticks, a scheduler of the badge's own.
    private let ticker: any Scheduler
    // pointer is the pointer position at the previous tick.
    private var pointer: Point?
    // settled reports whether the badge was already worked out for the current rest.
    private var settled = false
    // running reports whether the ticks are on.
    public private(set) var running = false

    // init builds a badge on platform and anchors that ticks on its own scheduler from the timers.
    public init(engine: Engine, platform: Platform, anchors: Anchors) {
        self.engine = engine
        self.platform = platform
        self.anchors = anchors
        ticker = platform.timers.scheduler()
    }

    // sync starts the ticks when the badge choice is on and this platform has a badge, and stops them
    // and hides the badge otherwise. The engine calls it after init, save and reload.
    public func sync() {
        let on = anchors.choices.stacking.badge && engine.features.contains(.badge)
        guard on != running else { return }
        running = on
        pointer = nil
        settled = false
        if on {
            schedule()
        } else {
            ticker.cancel()
            hide()
        }
    }

    // schedule sets the next tick Pace.pollSeconds from now.
    private func schedule() {
        ticker.schedule(at: platform.clock.now + Pace.pollSeconds) { [weak self] in self?.tick() }
    }

    // tick runs once per Pace.pollSeconds while running: it reads the pointer, hides the badge on a
    // move of more than restMove or a held button, and on the first tick of a rest counts the stack
    // whose front window has its top-left corner under the pointer from one scan and shows the count
    // on its front window.
    private func tick() {
        guard running else { return }
        schedule()
        let p = platform.pointer.position
        guard !platform.pointer.buttonDown else {
            hide()
            pointer = nil
            return
        }
        defer { pointer = p }
        guard let last = pointer, abs(p.x - last.x) <= Self.restMove, abs(p.y - last.y) <= Self.restMove else {
            hide()
            settled = false
            return
        }
        guard !settled else { return }
        settled = true
        let list = platform.windows.scan(platform.screens.current(), full: false).windows.map(\.frame)
        guard let i = Tile.hovered(at: p, frames: list, gap: anchors.choices.gapPx) else { return }
        let n = Tile.stack(anchorOf: i, among: list, choices: anchors.choices.stacking).count
        if n > 1 {
            platform.badge.show(n, at: list[i], palette: .harbor)
        }
    }

    // hide takes the badge off screen.
    public func hide() {
        platform.badge.hide()
    }
}
