import MooringsCore
import MooringsEngine

extension Scenarios {
    // pausedMovesNothing pins an app with the anchor weighed, puts a second window of it on the strip
    // by hand, and proves no pass moves any window in 4 s.
    static func pausedMovesNothing(_ s: Stage) {
        guard let (_, strip, _) = s.pin(paused: true), let second = s.open("second window") else { return }
        let onStrip = Frame(x: strip.x + 10, y: strip.y + 10, w: 300, h: 300)
        guard s.place(second.id, at: onStrip, "second window on the strip") else { return }
        let put = s.frame(second.id)
        let t0 = s.host.now
        s.hold(4)
        let moved = s.moves.filter { $0.t >= t0 }
        if !moved.isEmpty {
            s.fail("a paused engine moves nothing in 4 s", "\(moved.count) moves, first of window \(moved[0].id)")
        }
        s.note("second", s.frame(second.id))
        if !Contract.near(s.frame(second.id), put) {
            s.fail(
                "a window on the strip stays put while paused, 1 point",
                "put \(Contract.show(put)), now \(Contract.show(s.frame(second.id)))")
        }
    }
}
