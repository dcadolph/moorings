import MooringsCore
import MooringsEngine

// KeysContract checks that a Keys grab counts its keys, delivers a grabbed press by tag, delivers
// nothing after ungrab, and spells a shortcut.
public enum KeysContract {
    // keys are the keys the suite grabs: an arrow alone and one with Shift, as a grid hold takes them.
    static let keys = [
        GrabKey(key: "left", modifiers: [], tag: "move-left"),
        GrabKey(key: "right", modifiers: .shift, tag: "grow-right"),
    ]

    // run checks subject while host runs the platform and returns every rule it broke.
    public static func run(_ subject: Keys, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        var got: [String] = []
        defer { subject.ungrab() }
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
        if subject.spell(Shortcut(mods: [.ctrl, .alt], key: "left")).isEmpty {
            fail("spell writes a shortcut", "empty")
        }
        return out
    }
}
