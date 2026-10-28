import MooringsCore
import MooringsEngine

// EventSourceContract checks that an EventSource reports a window shown, moved and destroyed within
// 1 s each, delivers nothing once stopped, and delivers again once restarted. It is the rule that
// catches a hook that silently dies.
public enum EventSourceContract {
    // run checks subject over windows host opens, read and closed through store, and returns every
    // rule it broke.
    public static func run(_ subject: EventSource, store: WindowStore, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        defer {
            subject.stop()
            host.finish()
        }
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        let screens = host.screens()
        var got: [WindowEvent] = []
        subject.start { got.append($0) }
        guard let a = host.open() else {
            fail("the host opens a window", "none opened")
            return out
        }
        _ = host.wait(until: host.now + 1) { store.scan(screens, full: true).windows.contains { $0.id == a } }
        subject.watch(store.scan(screens, full: true))
        guard let b = host.open() else {
            fail("the host opens a second window", "none opened")
            return out
        }
        if !host.wait(until: host.now + 1, { got.contains(.shown(b)) }) {
            fail("a window the host opens delivers shown within 1 s", "got \(got)")
        }
        let moved = "a host nudge delivers moved within 1 s"
        if host.nudge(b) {
            if !host.wait(until: host.now + 1, { got.contains(.moved(b)) }) {
                fail(moved, "got \(got)")
            }
        } else {
            Contract.skip(moved, "the host cannot move a window from outside the store")
        }
        store.close(b)
        if !host.wait(until: host.now + 1, { got.contains(.destroyed(b)) }) {
            fail("a host close delivers destroyed within 1 s", "got \(got)")
        }
        subject.stop()
        got = []
        _ = host.open()
        _ = host.nudge(a)
        _ = host.wait(until: host.now + 1) { false }
        if !got.isEmpty {
            fail("nothing is delivered in 1 s after stop", "got \(got)")
        }
        subject.start { got.append($0) }
        subject.watch(store.scan(screens, full: true))
        guard let d = host.open() else {
            fail("the host opens a window after the restart", "none opened")
            return out
        }
        if !host.wait(until: host.now + 1, { got.contains(.shown(d)) }) {
            fail("a stopped and restarted source delivers again", "got \(got)")
        }
        return out
    }
}
