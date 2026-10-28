import MooringsCore
import MooringsEngine

// ChoicesStoreContract checks that a ChoicesStore handed over empty storage loads the defaults, gives back
// what was saved, keeps the last save, and reports a change only when the choices moved under it.
public enum ChoicesStoreContract {
    // run checks subject, which must start over empty storage, and returns every rule it broke.
    public static func run(_ subject: ChoicesStore, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        if subject.load() != Choices() {
            fail("load with nothing saved gives the defaults", "got something else")
        }
        if subject.changed() {
            fail("changed is false right after load", "changed")
        }
        var a = Choices()
        a.paused = true
        a.gapPx = 12
        a.snap = false
        var b = Choices()
        b.fullscreenFills = !b.fullscreenFills
        b.gapPx = 7
        b.checkUpdates = !b.checkUpdates
        do {
            try subject.save(a)
        } catch {
            fail("save succeeds", "threw \(error)")
            return out
        }
        if subject.load() != a {
            fail("save then load gives back what was saved", "loaded something else")
        }
        do {
            try subject.save(b)
        } catch {
            fail("save succeeds", "threw \(error)")
            return out
        }
        if subject.load() != b {
            fail("a second save wins", "loaded something else")
        }
        try? subject.save(a)
        if subject.changed() {
            fail("changed is false after save", "changed")
        }
        let moved = "changed is true after the host rewrites the choices"
        guard host.touchChoices() else {
            Contract.skip(moved, "the host cannot rewrite the choices")
            return out
        }
        if !subject.changed() {
            fail(moved, "unchanged")
        }
        _ = subject.load()
        if subject.changed() {
            fail("changed is false right after load", "changed after a rewrite and a load")
        }
        return out
    }
}
