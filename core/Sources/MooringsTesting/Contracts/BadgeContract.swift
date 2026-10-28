import MooringsCore
import MooringsEngine

// BadgeContract checks that a BadgeView shows, moves and hides the stack badge without taking the
// focus from the window under it.
public enum BadgeContract {
    // run checks subject over a focused host window read through store and returns every rule it broke.
    public static func run(_ subject: BadgeView, store: WindowStore, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        defer {
            subject.hide()
            host.finish()
        }
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        guard let a = Contract.focus(store, host, &out) else { return out }
        let screens = host.screens()
        let area = screens.usable[0]
        let first = BadgeMark(count: 2, front: Frame(x: area.x + 20, y: area.y + 20, w: 300, h: 200))
        let second = BadgeMark(count: 3, front: Frame(x: area.x + 400, y: area.y + 20, w: 300, h: 200))
        subject.show(first.count, at: first.front, palette: .harbor)
        if subject.shown != first {
            fail("show then shown equals the mark", "asked \(first) shown \(show(subject.shown))")
        }
        subject.show(second.count, at: second.front, palette: .harbor)
        if subject.shown != second {
            fail("a second show moves the badge", "asked \(second) shown \(show(subject.shown))")
        }
        _ = host.wait(until: host.now + 0.25) { false }
        if store.scan(screens, full: true).focused?.id != a {
            fail("the badge never takes focus from the host window", "focus moved off \(a)")
        }
        subject.hide()
        if subject.shown != nil {
            fail("hide clears shown", "shown \(show(subject.shown))")
        }
        return out
    }

    // show writes a mark, or none, for a failure detail.
    private static func show(_ m: BadgeMark?) -> String {
        m.map { "\($0.count) at \($0.front)" } ?? "none"
    }
}
