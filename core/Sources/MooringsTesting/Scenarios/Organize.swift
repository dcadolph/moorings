import MooringsCore
import MooringsEngine

extension Scenarios {
    // organize stacks three free windows in the channel 5 points apart, runs Tile columns on the front
    // one and proves they take equal columns of the channel's full height, left to right in their order
    // by x, then that Undo puts each back at its frame from before the tile, all within 1 s, 1 point.
    // Tile columns tiles every free window on the screen, so on a host with other windows there the
    // columns are as many as the windows, and three alone also sit flush with both channel edges. Undo
    // runs even when the tile check fails, so a failed run leaves no window of the host tiled.
    static func organize(_ s: Stage) {
        s.choose { _ in }
        let screens = s.host.screens()
        guard let i = screens.ultrawide else {
            s.fail("the host has an ultrawide", "none at the host's min aspect")
            return
        }
        let c = s.engine.organizer.area(screens, i)
        s.note("channel", c)
        let before = (0..<3).map { Frame(x: c.x + 100 + 5 * Double($0), y: c.y + 100 + 5 * Double($0), w: 700, h: 500) }
        var pads: [WindowInfo] = []
        for (k, f) in before.enumerated() {
            guard let pad = s.open("window \(k + 1)"), s.place(pad.id, at: f, "window \(k + 1)") else { return }
            pads.append(pad)
        }
        let stacked = s.host.wait(until: s.host.now + 1) {
            zip(pads, before).allSatisfy { Contract.near(s.frame($0.id), $1) }
        }
        guard stacked else {
            s.fail(
                "the store reads the stacked windows within 1 s, 1 point",
                "want \(before), got \(pads.map { Contract.show(s.frame($0.id)) })")
            return
        }
        let n = s.engine.platform.windows.scan(screens, full: true).windows.filter {
            !s.engine.anchors.pinned($0) && !$0.isFullScreen && screens.index($0.frame) == i
        }.count
        s.measure("\(n) free windows on the ultrawide")
        let ran = s.engine.actions.run("tile-columns", window: pads[2].id)
        let tiled = s.host.wait(until: s.host.now + 1) {
            columns(pads.compactMap { s.frame($0.id) }, of: n, in: c)
        }
        for (k, pad) in pads.enumerated() {
            s.note("column \(k + 1)", s.frame(pad.id))
        }
        if !ran || !tiled {
            s.fail(
                "tile columns gives \(n) equal columns across the channel within 1 s, 1 point",
                "ran \(ran), channel \(c), windows \(pads.map { Contract.show(s.frame($0.id)) })")
        }
        s.engine.organizer.undo()
        let back = s.host.wait(until: s.host.now + 1) {
            zip(pads, before).allSatisfy { Contract.near(s.frame($0.id), $1) }
        }
        if !back {
            s.fail(
                "undo puts every tiled window back within 1 s, 1 point",
                "before \(before), now \(pads.map { Contract.show(s.frame($0.id)) })")
        }
    }

    // columns reports whether f are three columns of the n equal ones that fill c, left to right in
    // their order and of its full height, flush with both edges of c when n is 3, each within 1 point.
    static func columns(_ f: [Frame], of n: Int, in c: Frame) -> Bool {
        guard f.count == 3, n >= 3, let w = Tile.columns(c, n).first?.w else { return false }
        let fit = f.allSatisfy { abs($0.w - w) <= 1 && abs($0.y - c.y) <= 1 && abs($0.h - c.h) <= 1 }
        let flush = n > 3 || (abs(f[0].x - c.x) <= 1 && abs(f[2].x + f[2].w - (c.x + c.w)) <= 1)
        return fit && f[0].x < f[1].x && f[1].x < f[2].x && flush
    }
}
