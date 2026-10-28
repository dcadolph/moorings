import MooringsCore
import MooringsEngine

extension Scenarios {
    // nudgedPinReleasesInGrace moves a pin by hand once its 2 s grace is over and proves the pass
    // releases it within 1 s, once, and leaves it where the hand put it for 2 s.
    static func nudgedPinReleasesInGrace(_ s: Stage) {
        guard let (pad, _, at) = s.pin() else { return }
        _ = s.host.wait(until: at + graceSeconds) { false }
        guard s.host.nudge(pad.id) else {
            s.fail("the host moves the pin by hand", "window \(pad.id) not moved")
            return
        }
        let tn = s.host.now
        let put = s.frame(pad.id)
        s.note("hand move", put)
        let released = s.host.wait(until: tn + reactSeconds) { s.releases.contains { $0.id == pad.id } }
        guard released, let rel = s.releases.first(where: { $0.id == pad.id }) else {
            s.fail("a pin moved by hand is released within 1 s", "no release, pin \(Contract.show(s.frame(pad.id)))")
            return
        }
        s.measure("pin released \(seconds(rel.t - tn)) s after the hand move")
        s.hold(2)
        let count = s.releases.filter { $0.id == pad.id }.count
        if count != 1 {
            s.fail("a pin moved by hand is released once", "released \(count) times")
        }
        s.note("final", s.frame(pad.id))
        if !Contract.near(s.frame(pad.id), put) {
            s.fail(
                "a released pin stays where the hand put it for 2 s, 1 point",
                "put \(Contract.show(put)), now \(Contract.show(s.frame(pad.id)))")
        }
    }
}
