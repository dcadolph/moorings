import MooringsCore
import MooringsEngine

extension Scenarios {
    // tilingKeepsLayout turns on tiling in columns with two windows in the channel and proves the
    // tiler keeps equal columns as a third window opens and one closes, then that a window dragged out
    // of its column is left where it was dropped while the rest close up, each within 1 s, 1 point.
    // Tiling takes every free window on the screen, so the columns are as many as those windows, and
    // only the scenario's own windows are judged, since another window may hold its minimum size.
    static func tilingKeepsLayout(_ s: Stage) {
        s.choose { _ in }
        let screens = s.host.screens()
        guard let i = screens.host else {
            s.fail("the host has an ultrawide", "none at the host's min aspect")
            return
        }
        let c = s.engine.organizer.area(screens, i)
        s.note("channel", c)
        var pads: [WindowInfo] = []
        for k in 0..<2 {
            let f = Frame(x: c.x + 100 + 5 * Double(k), y: c.y + 100 + 5 * Double(k), w: 500, h: 350)
            guard let pad = s.open("window \(k + 1)"), s.place(pad.id, at: f, "window \(k + 1)") else { return }
            pads.append(pad)
        }
        s.choose { $0.tiling.mode = .columns }
        guard tiled(s, pads, on: i, in: c, "two windows after columns is chosen") else { return }
        guard let third = s.open("window 3"),
            s.place(third.id, at: Frame(x: c.x + 150, y: c.y + 150, w: 500, h: 350), "window 3")
        else { return }
        pads.append(third)
        guard tiled(s, pads, on: i, in: c, "three windows after a third opens") else { return }
        s.engine.platform.windows.close(pads[0].id)
        pads.removeFirst()
        guard tiled(s, pads, on: i, in: c, "two windows after one closes") else { return }
        guard let f = s.frame(pads[0].id) else {
            s.fail("the store reads window 2 before the drag", "window \(pads[0].id) gone")
            return
        }
        let to = Point(x: c.x + c.w / 2, y: c.y + c.h / 2)
        guard s.drag(pads[0], to: to, "window 2") else { return }
        let dropped = s.frame(pads[0].id)
        s.note("dropped", dropped)
        guard let dropped, !Contract.near(dropped, f) else {
            s.fail("the drag moves window 2 off its column", "column \(f), now \(Contract.show(dropped))")
            return
        }
        guard tiled(s, [pads[1]], on: i, in: c, leaving: [pads[0].id], "the window left after the other is dragged out")
        else { return }
        s.hold(reactSeconds)
        if !Contract.near(s.frame(pads[0].id), dropped) {
            s.fail(
                "a window dragged out of its column stays where it was dropped for 1 s, 1 point",
                "dropped \(dropped), now \(Contract.show(s.frame(pads[0].id)))")
        }
    }

    // tiled waits up to 1 s for pads to sit on distinct frames of the columns layout of every window
    // tiling should take on screen i, leaving out the windows in leaving, records the frames under
    // label, and records a failure when they do not. It reports whether they did.
    static func tiled(
        _ s: Stage, _ pads: [WindowInfo], on i: Int, in c: Frame, leaving: Set<WindowID> = [], _ label: String
    ) -> Bool {
        var want: [Frame] = []
        let ok = s.host.wait(until: s.host.now + reactSeconds) {
            want = columnsLayout(s, on: i, in: c, leaving: leaving)
            var free = want
            for pad in pads {
                guard let f = s.frame(pad.id), let k = free.firstIndex(where: { Contract.near(f, $0) }) else {
                    return false
                }
                free.remove(at: k)
            }
            return true
        }
        for (k, pad) in pads.enumerated() {
            s.note("\(label): window \(k + 1)", s.frame(pad.id))
        }
        s.measure("\(label): \(want.count) columns")
        if !ok {
            s.fail(
                "tiling in columns gives \(label) equal columns within 1 s, 1 point",
                "columns \(want), windows \(pads.map { Contract.show(s.frame($0.id)) })")
        }
        return ok
    }

    // columnsLayout returns the columns tiling should give the windows on screen i that are free, not
    // full screen, not a file panel, not stashed, and not in leaving.
    static func columnsLayout(_ s: Stage, on i: Int, in c: Frame, leaving: Set<WindowID>) -> [Frame] {
        let screens = s.host.screens()
        let anchors = s.engine.anchors
        let n = s.engine.platform.windows.scan(screens, full: true).windows.filter {
            !$0.isFilePanel && !$0.isFullScreen && !anchors.pinned($0) && !anchors.stashed.contains($0.id)
                && !anchors.isCastOff($0.id) && !leaving.contains($0.id) && screens.index($0.frame) == i
        }.count
        return Tiling.layout(.columns, c, n, ratio: anchors.choices.tiling.ratio, gap: anchors.choices.gapPx)
    }
}
