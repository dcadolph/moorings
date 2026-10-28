import MooringsCore
import MooringsEngine

extension Scenarios {
    // refusedWindowTriedOnce pins the app of a window that refuses every move and proves the passes try
    // it once and leave it at its frame for 5 s. A host that cannot open such a window skips it.
    static func refusedWindowTriedOnce(_ s: Stage) {
        guard let id = s.host.openRefusing() else {
            s.skip("host cannot open a refusing window")
            return
        }
        let screens = s.host.screens()
        var found: WindowInfo?
        _ = s.host.wait(until: s.host.now + 2) {
            found = s.engine.platform.windows.scan(screens, full: true).windows.first { $0.id == id }
            return found != nil
        }
        guard let w = found else {
            s.fail("the store reads the refusing window within 2 s", "window \(id) never read")
            return
        }
        s.note("start", w.frame)
        let t0 = s.host.now
        s.choose { $0.slots = [.leftTop: w.bundle] }
        s.hold(5)
        let tries = s.moves.filter { $0.id == id && $0.t >= t0 }
        s.measure("\(tries.count) tries in 5 s")
        if tries.count != 1 {
            s.fail("a window that refuses a move is tried once in 5 s", "\(tries.count) tries")
        }
        s.note("final", s.frame(id))
        if !Contract.near(s.frame(id), w.frame) {
            s.fail(
                "a window that refuses stays at its frame, 1 point",
                "start \(w.frame), now \(Contract.show(s.frame(id)))")
        }
    }
}
