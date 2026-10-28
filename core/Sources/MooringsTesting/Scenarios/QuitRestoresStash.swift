import MooringsCore
import MooringsEngine

extension Scenarios {
    // quitRestoresStash stashes a free window and proves the engine's shutdown, which Quit runs on every
    // platform, puts it back at its frame within 1 s, 1 point, and leaves no pass pending.
    static func quitRestoresStash(_ s: Stage) {
        s.choose { _ in }
        guard let pad = s.open("window"), let original = s.frame(pad.id) else { return }
        s.note("original", original)
        guard s.engine.stasher.stash(pad, edge: nil) else {
            s.fail("a free window stashes", "window \(pad.id) at \(original) not stashed")
            return
        }
        s.note("stashed", s.frame(pad.id))
        if Contract.near(s.frame(pad.id), original) {
            s.fail("a stashed window leaves its frame", "still at \(original), so the check proves nothing")
            return
        }
        let t = s.host.now
        s.engine.shutdown()
        if let due = s.engine.passes.due {
            s.fail("shutdown leaves no pass pending", "a pass is due at \(due)")
        }
        let back = s.host.wait(until: t + reactSeconds) { Contract.near(s.frame(pad.id), original) }
        s.note("after shutdown", s.frame(pad.id))
        if !back {
            s.fail(
                "shutdown puts every stashed window back within 1 s, 1 point",
                "original \(original), now \(Contract.show(s.frame(pad.id)))")
        }
    }
}
