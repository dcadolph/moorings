import MooringsCore
import MooringsEngine

extension Scenarios {
    // badgeCounts turns the stack badge on, stacks three free windows in the channel 5 points apart
    // with the front one raised, and rests the pointer 10 points inside the front window's corner. It
    // proves the badge shows 3 on the front window within 1 s, its frame within 1 point, and that a
    // move past the badge's rest distance hides it within 1 s.
    static func badgeCounts(_ s: Stage) {
        s.choose { $0.stacking.badge = true }
        let screens = s.host.screens()
        guard let i = screens.ultrawide else {
            s.fail("the host has an ultrawide", "none at the host's min aspect")
            return
        }
        let c = s.engine.organizer.area(screens, i)
        let frames = (0..<3).map { Frame(x: c.x + 100 + 5 * Double($0), y: c.y + 100 + 5 * Double($0), w: 700, h: 500) }
        var pads: [WindowInfo] = []
        for (k, f) in frames.enumerated() {
            guard let pad = s.open("window \(k + 1)"), s.place(pad.id, at: f, "window \(k + 1)") else { return }
            pads.append(pad)
        }
        guard let front = pads.last, let corner = frames.last else { return }
        s.engine.platform.windows.raise(front.id)
        let stacked = s.host.wait(until: s.host.now + 1) {
            zip(pads, frames).allSatisfy { Contract.near(s.frame($0.id), $1) }
                && s.engine.platform.windows.scan(screens, full: true).focused?.id == front.id
        }
        guard stacked else {
            s.fail(
                "the store reads the stacked windows with the front one focused within 1 s, 1 point",
                "want \(frames), got \(pads.map { Contract.show(s.frame($0.id)) })")
            return
        }
        s.note("front", corner)
        let rest = Point(x: corner.x + 10, y: corner.y + 10)
        s.engine.platform.pointer.warp(rest)
        let shown = s.host.wait(until: s.host.now + 1) {
            guard let m = s.engine.platform.badge.shown else { return false }
            return m.count == 3 && Contract.near(m.front, corner)
        }
        let mark = s.engine.platform.badge.shown
        s.measure("badge \(mark.map { "\($0.count) on \(Contract.show($0.front))" } ?? "hidden")")
        guard shown else {
            s.fail(
                "a pointer resting at a stack's front corner shows its count, 3, on the front window within 1 s",
                "front \(corner), badge \(mark.map { "\($0.count) on \(Contract.show($0.front))" } ?? "hidden")")
            return
        }
        s.engine.platform.pointer.warp(Point(x: rest.x + StackBadge.restMove + 40, y: rest.y + 40))
        let hidden = s.host.wait(until: s.host.now + 1) { s.engine.platform.badge.shown == nil }
        if !hidden {
            s.fail("a pointer move past the rest distance hides the badge within 1 s", "still shown")
        }
    }
}
