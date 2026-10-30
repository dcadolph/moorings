import MooringsCore
import MooringsEngine

// KeysContract checks that a Keys grab counts its keys, delivers a grabbed press by tag, delivers
// nothing after ungrab, delivers a claimed press by tag through a grab and an ungrab, delivers
// nothing after unclaim, spells a shortcut, delivers a bound shortcut's action, and delivers nothing
// once an empty map replaces the binding.
public enum KeysContract {
    // keys are the keys the suite grabs: an arrow alone and one with Shift, as a grid hold takes them.
    static let keys = [
        GrabKey(key: "left", modifiers: [], tag: "move-left"),
        GrabKey(key: "right", modifiers: .shift, tag: "grow-right"),
    ]

    // claimKey is the key the suite claims, one no grab above uses.
    static let claimKey = GrabKey(key: "up", modifiers: [], tag: "claim-up")

    // bound is the shortcut the suite binds, one no platform or common app keeps for itself, and the
    // press that sends it.
    static let bound = (
        name: "contract-bound", shortcut: Shortcut(mods: [.ctrl, .alt, .shift], key: "j"),
        press: GrabKey(key: "j", modifiers: [.control, .option, .shift], tag: "contract-bound")
    )

    // run checks subject while host runs the platform and returns every rule it broke. actions lists
    // the action names subject's bound shortcuts delivered so far.
    public static func run(_ subject: Keys, host: ContractHost, actions: () -> [String]) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        var got: [String] = []
        defer {
            subject.ungrab()
            subject.unclaim()
        }
        let taken = subject.grab(keys) { got.append($0) }
        if taken != keys.count {
            fail("grab returns how many keys it took", "asked \(keys.count) took \(taken)")
        }
        let delivery = "a grabbed key delivers its tag within 250 ms"
        if host.press(keys[1]) {
            if !host.wait(until: host.now + 0.25, { got.contains(keys[1].tag) }) {
                fail(delivery, "got \(got)")
            }
        } else {
            Contract.skip(delivery, "the host cannot press a key")
        }
        subject.ungrab()
        got = []
        if host.press(keys[0]) {
            _ = host.wait(until: host.now + 0.25) { false }
            if !got.isEmpty {
                fail("after ungrab a press delivers nothing", "got \(got)")
            }
        }
        var claimGot: [String] = []
        let claimed = subject.claim([claimKey]) { claimGot.append($0) }
        if claimed != 1 {
            fail("claim returns how many keys it took", "asked 1 took \(claimed)")
        }
        let claimDelivery = "a claimed key delivers its tag within 250 ms"
        let claimSurvives = "a grab then ungrab between the claim and the press leaves it delivering"
        let claimGone = "after unclaim a press delivers nothing"
        if host.press(claimKey) {
            if !host.wait(until: host.now + 0.25, { claimGot.contains(claimKey.tag) }) {
                fail(claimDelivery, "got \(claimGot)")
            }
            claimGot = []
            _ = subject.grab(keys) { _ in }
            subject.ungrab()
            _ = host.press(claimKey)
            if !host.wait(until: host.now + 0.25, { claimGot.contains(claimKey.tag) }) {
                fail(claimSurvives, "got \(claimGot)")
            }
            subject.unclaim()
            claimGot = []
            _ = host.press(claimKey)
            _ = host.wait(until: host.now + 0.25) { false }
            if !claimGot.isEmpty {
                fail(claimGone, "got \(claimGot)")
            }
        } else {
            Contract.skip(claimDelivery, "the host cannot press a key")
            Contract.skip(claimSurvives, "the host cannot press a key")
            Contract.skip(claimGone, "the host cannot press a key")
        }
        if subject.spell(Shortcut(mods: [.ctrl, .alt], key: "left")).isEmpty {
            fail("spell writes a shortcut", "empty")
        }
        defer { subject.bind([:]) }
        subject.bind([bound.name: bound.shortcut])
        let action = "a bound shortcut delivers its action within 250 ms"
        let unbound = "bind of an empty map after a bind leaves no shortcut delivering"
        guard host.press(bound.press) else {
            Contract.skip(action, "the host cannot press a key")
            Contract.skip(unbound, "the host cannot press a key")
            return out
        }
        if !host.wait(until: host.now + 0.25, { actions().contains(bound.name) }) {
            fail(action, "got \(actions())")
        }
        subject.bind([:])
        let before = actions().count
        if host.press(bound.press) {
            _ = host.wait(until: host.now + 0.25) { false }
            if actions().count != before {
                fail(unbound, "got \(actions().dropFirst(before))")
            }
        }
        return out
    }
}
