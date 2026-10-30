import MooringsCore
import MooringsEngine

extension Scenarios {
    // eventsWakeAndRestHolds runs the passes with nothing anchored, moves one window by hand, and
    // proves the move arrives as an event within 1 s, wakes 1 to 3 passes, and that no pass runs more
    // than 1 s after the event that caused it, or 1.5 s after the start before any event. An app's
    // launch holds the passes at Pace.busySeconds for Pace.launchSeconds by design, so it first
    // waits out a launch window still open, such as the one TextEdit's launch opens on a live host.
    static func eventsWakeAndRestHolds(_ s: Stage) {
        s.choose { _ in }
        guard let pad = s.open("window") else { return }
        let launch = s.engine.passes.launching - s.host.now
        if launch > 0 {
            s.measure("waited \(seconds(launch)) s for a launch window to close")
            s.hold(launch)
        }
        s.hold(1.5)
        let t0 = s.host.now
        let firstPass = s.passes.count, firstEvent = s.events.count
        s.hold(1.5)
        guard s.host.nudge(pad.id) else {
            s.fail("the host moves the window by hand", "window \(pad.id) not moved")
            return
        }
        let tn = s.host.now
        s.note("hand move", s.frame(pad.id))
        s.hold(3)
        let events = Array(s.events[firstEvent...]), passes = Array(s.passes[firstPass...])
        let names = { (e: WindowEvent) -> Bool in
            switch e {
            case let .moved(id), let .shown(id), let .destroyed(id), let .focused(id): id == pad.id
            default: false
            }
        }
        guard let moved = events.first(where: { $0.event == .moved(pad.id) && $0.t >= tn }), moved.t - tn <= 1 else {
            s.fail("a window moved by hand delivers moved within 1 s", "events \(events.map(\.event))")
            return
        }
        let cause = { (t: Double) in events.last { $0.t <= t } }
        let forMove = passes.filter { t in t >= tn && cause(t).map { names($0.event) } == true }
        s.measure("\(forMove.count) passes for one move, moved delivered \(seconds(moved.t - tn)) s after it")
        if !(1...3).contains(forMove.count) {
            s.fail("one move wakes 1 to 3 passes", "\(forMove.count) passes at \(forMove.map { seconds($0 - tn) })")
        }
        let idle = passes.filter { t in
            guard let c = cause(t) else { return t > t0 + 1.5 }
            return t - c.t > 1
        }
        if !idle.isEmpty {
            // The events since the start name what kept the passes running, such as another app's
            // launch, which holds them at Pace.busySeconds for Pace.launchSeconds.
            let seen = events.map { "\(seconds($0.t - t0)) \($0.event)" }
            s.fail(
                "no pass runs more than 1 s after the last window event",
                "\(idle.count) idle passes at \(idle.map { seconds($0 - t0) }) s after the start, "
                    + "passes \(passes.map { seconds($0 - t0) }), events \(seen)")
        }
    }
}
