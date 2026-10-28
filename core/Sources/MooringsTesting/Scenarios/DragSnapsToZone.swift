import MooringsCore
import MooringsEngine

extension Stage {
    // dragged opens a window with the default choices, places it 200 by 150 points into wide at 500 by
    // 350, and returns it with the channel's left half, the frame a drop at the left edge gives it.
    // It returns nil when any of that failed.
    func dragged(_ wide: Frame) -> (pad: WindowInfo, half: Frame)? {
        choose { _ in }
        guard let pad = open("dragged window") else { return nil }
        let start = Frame(x: wide.x + 200, y: wide.y + 150, w: 500, h: 350)
        guard place(pad.id, at: start, "dragged window") else { return nil }
        guard host.wait(until: host.now + 1, { Contract.near(frame(pad.id), start) }) else {
            fail("the dragged window reads back where the host placed it within 1 s", "start \(start)")
            return nil
        }
        let ch = engine.anchors.channel(wide)
        note("channel", ch)
        let half = Frame(x: ch.x, y: ch.y, w: (ch.w / 2).rounded(.down), h: ch.h)
        note("half", half)
        return (pad, half)
    }
}

extension Scenarios {
    // dragSnapsToZone drags a window by its title bar to the left edge and proves the drop lands on
    // the left-half zone, the window takes the channel's left half within 1.5 s and 1 point, and the
    // footprint is gone after the drop.
    static func dragSnapsToZone(_ s: Stage) {
        guard let wide = s.wide(), let full = s.full(), let (pad, half) = s.dragged(wide) else { return }
        guard s.drag(pad, to: edge(full), "dragged window") else { return }
        let on = s.drops.last?.on
        if on != .zone("left-half") {
            s.fail("the drop at the left edge lands on left-half", "dropped on \(String(describing: on))")
        }
        let landed = s.host.wait(until: s.host.now + 1.5) { Contract.near(s.frame(pad.id), half) }
        s.note("after", s.frame(pad.id))
        if !landed {
            s.fail(
                "the dropped window takes the channel's left half within 1.5 s, 1 point",
                "half \(half), window \(Contract.show(s.frame(pad.id)))")
        }
        if let shown = s.engine.platform.overlay.shown {
            s.fail("the footprint hides on the drop", "still shown at \(shown)")
        }
    }
}
