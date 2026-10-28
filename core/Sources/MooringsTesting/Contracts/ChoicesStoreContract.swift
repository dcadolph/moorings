import Foundation

import MooringsCore
import MooringsEngine

// ChoicesStoreContract checks that a ChoicesStore handed over empty storage loads the defaults, gives back
// what was saved, keeps the last save, reports a change only when the choices moved under it, and moves
// a payload it cannot read aside.
public enum ChoicesStoreContract {
    // run checks subject, which must start over empty storage, and returns every rule it broke.
    public static func run(_ subject: ChoicesStore, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        let first = subject.load()
        if first.choices != Choices() {
            fail("load with nothing saved gives the defaults", "got something else")
        }
        if let reason = first.fallback {
            fail("nothing saved is no fallback", reason)
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
        if subject.load().choices != a {
            fail("save then load gives back what was saved", "loaded something else")
        }
        do {
            try subject.save(b)
        } catch {
            fail("save succeeds", "threw \(error)")
            return out
        }
        if subject.load().choices != b {
            fail("a second save wins", "loaded something else")
        }
        try? subject.save(a)
        if subject.changed() {
            fail("changed is false after save", "changed")
        }
        let moved = "changed is true after the host rewrites the choices"
        if host.touchChoices() {
            if !subject.changed() {
                fail(moved, "unchanged")
            }
            _ = subject.load()
            if subject.changed() {
                fail("changed is false right after load", "changed after a rewrite and a load")
            }
        } else {
            Contract.skip(moved, "the host cannot rewrite the choices")
        }
        let spoiled = "a corrupt payload loads the defaults with a reason and moves aside"
        let payload = Data(#"{"gapPx":4,"slots":{"left-top":"#.utf8)
        guard host.spoilChoices(payload) else {
            Contract.skip(spoiled, "the host cannot write a payload")
            return out
        }
        let bad = subject.load()
        if bad.choices != Choices() || bad.fallback == nil {
            fail(
                spoiled,
                "loaded \(bad.choices == Choices() ? "the defaults" : "other choices"), fallback \(bad.fallback ?? "none")"
            )
        }
        if host.choicesAside() != payload {
            fail(spoiled, "aside holds \(host.choicesAside().map { "\($0.count) bytes" } ?? "nothing")")
        }
        let after = subject.load()
        if after.choices != Choices() || after.fallback != nil {
            fail(spoiled, "the next load fell back again: \(after.fallback ?? "other choices")")
        }
        return out
    }
}
