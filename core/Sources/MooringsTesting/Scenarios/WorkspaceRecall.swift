import MooringsCore
import MooringsEngine

extension Scenarios {
    // workspaceRecall puts two free windows at two frames in the channel, saves them as a workspace,
    // moves both from outside the store, and proves a recall puts each back at its saved frame within
    // 1 s, 1 point. It also proves the workspace saved both windows, and more on a host with others open.
    static func workspaceRecall(_ s: Stage) {
        s.choose { _ in }
        let screens = s.host.screens()
        guard let i = screens.ultrawide else {
            s.fail("the host has an ultrawide", "none at the host's min aspect")
            return
        }
        let c = s.engine.organizer.area(screens, i)
        let saved = [
            Frame(x: c.x + 100, y: c.y + 100, w: 700, h: 500), Frame(x: c.x + 900, y: c.y + 200, w: 600, h: 400),
        ]
        let moved = [
            Frame(x: c.x + 300, y: c.y + 300, w: 400, h: 300), Frame(x: c.x + 1200, y: c.y + 500, w: 500, h: 300),
        ]
        var pads: [WindowInfo] = []
        for (k, f) in saved.enumerated() {
            guard let pad = s.open("window \(k + 1)"), s.place(pad.id, at: f, "window \(k + 1)") else { return }
            pads.append(pad)
        }
        let at = { (frames: [Frame]) in zip(pads, frames).allSatisfy { Contract.near(s.frame($0.id), $1) } }
        guard s.host.wait(until: s.host.now + 1, { at(saved) }) else {
            s.fail(
                "the store reads the windows at their frames within 1 s, 1 point",
                "want \(saved), got \(pads.map { Contract.show(s.frame($0.id)) })")
            return
        }
        let name = "scenario"
        s.engine.workspaces.saveWorkspace(name)
        let kept = s.engine.anchors.choices.workspaces[name]?.windows.count ?? 0
        s.measure("workspace \(name) saved \(kept) windows")
        if kept < pads.count {
            s.fail("a saved workspace holds every free window", "\(kept) saved, \(pads.count) opened")
            return
        }
        for (pad, f) in zip(pads, moved) {
            guard s.place(pad.id, at: f, "window moved off its saved frame") else { return }
        }
        guard s.host.wait(until: s.host.now + 1, { at(moved) }) else {
            s.fail(
                "the store reads the moved windows within 1 s, 1 point",
                "want \(moved), got \(pads.map { Contract.show(s.frame($0.id)) })")
            return
        }
        let recalled = s.engine.workspaces.recall(name)
        let back = s.host.wait(until: s.host.now + 1) { at(saved) }
        for (k, pad) in pads.enumerated() {
            s.note("recalled \(k + 1)", s.frame(pad.id))
        }
        if !recalled || !back {
            s.fail(
                "a recall puts each saved window back within 1 s, 1 point",
                "recalled \(recalled), want \(saved), got \(pads.map { Contract.show(s.frame($0.id)) })")
        }
    }
}
