import MooringsCore
import MooringsEngine

extension Scenarios {
    // footprintFollowsDrag drags a window by its title bar to the left edge and proves the footprint
    // showed the left half the drop takes, within 1 point, before the drop.
    static func footprintFollowsDrag(_ s: Stage) {
        guard let wide = s.wide(), let full = s.full(), let (pad, half) = s.dragged(wide) else { return }
        guard s.drag(pad, to: edge(full), "dragged window") else { return }
        s.measure("footprint shown \(s.shows.count) times")
        s.note("footprint", s.shows.last)
        if !Contract.near(s.shows.last, half) {
            s.fail(
                "the footprint shows the left half the drop takes, 1 point",
                "half \(half), footprint \(Contract.show(s.shows.last))")
        }
    }
}
