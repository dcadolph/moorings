import MooringsCore
import MooringsEngine

// OverlayContract checks that an OverlayView shows, moves and hides the footprint without taking the
// focus from the window under it.
public enum OverlayContract {
    // run checks subject over a focused host window read through store and returns every rule it broke.
    public static func run(_ subject: OverlayView, store: WindowStore, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        defer {
            subject.hide()
            host.finish()
        }
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        guard let a = Contract.focus(store, host, &out) else { return out }
        let screens = host.screens()
        let area = screens.usable[0]
        let first = Frame(x: area.x + 20, y: area.y + 20, w: 300, h: 200)
        let second = Frame(x: area.x + 400, y: area.y + 20, w: 300, h: 200)
        subject.show(first, style: FootprintStyle(), palette: .harbor)
        if subject.shown != first {
            fail("show then shown equals the frame", "asked \(first) shown \(Contract.show(subject.shown))")
        }
        subject.show(second, style: FootprintStyle(), palette: .harbor)
        if subject.shown != second {
            fail("a second show moves the footprint", "asked \(second) shown \(Contract.show(subject.shown))")
        }
        _ = host.wait(until: host.now + 0.25) { false }
        if store.scan(screens, full: true).focused?.id != a {
            fail("the overlay never takes focus from the host window", "focus moved off \(a)")
        }
        subject.hide()
        if subject.shown != nil {
            fail("hide clears shown", "shown \(Contract.show(subject.shown))")
        }
        return out
    }
}
