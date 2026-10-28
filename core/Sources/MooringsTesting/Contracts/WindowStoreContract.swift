import MooringsCore
import MooringsEngine

// WindowStoreContract checks that a WindowStore lists, reads, moves, raises, minimizes and closes
// windows the way the engine relies on, each rule with its limit from the design's timing rules.
public enum WindowStoreContract {
    // run checks subject against windows host opens and returns every rule it broke.
    public static func run(_ subject: WindowStore, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        defer { host.finish() }
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        guard let a = Contract.focus(subject, host, &out) else { return out }
        let screens = host.screens()
        guard let wa = subject.scan(screens, full: true).windows.first(where: { $0.id == a }) else {
            fail("scan lists the host's window", "window \(a) missing")
            return out
        }
        if wa.frame.w <= 0 || wa.frame.h <= 0 {
            fail("scan gives the host's window a non-empty frame", "\(wa.frame)")
        }
        if !wa.isMain {
            fail("scan marks the host's only window main", "main false")
        }
        if !Contract.near(subject.frame(a), wa.frame) {
            fail("frame equals the scan within 1 px", "scan \(wa.frame) frame \(Contract.show(subject.frame(a)))")
        }
        let area = screens.usable[screens.index(wa.frame) ?? 0]
        let target = Frame(x: area.x + 40, y: area.y + 40, w: 640, h: 420)
        subject.move(a, to: target, from: wa.frame, behavior: Behaviors())
        if !host.wait(until: host.now + 0.25, { Contract.near(subject.frame(a), target) }) {
            fail("a move on a cooperative window reads back within 1 px inside 250 ms",
                 "asked \(target) got \(Contract.show(subject.frame(a)))")
        }
        if let min = host.minimum {
            let tiny = Frame(x: target.x, y: target.y, w: 1, h: 1)
            subject.move(a, to: tiny, from: target, behavior: Behaviors())
            _ = host.wait(until: host.now + 0.25) { subject.frame(a) != target }
            let got = subject.frame(a)
            if let got, got.w < min.w - 1 || got.h < min.h - 1 {
                fail("a move below the minimum keeps the minimum", "minimum \(min.w)x\(min.h) got \(got)")
            }
            let read = subject.scan(screens, full: true).windows.first { $0.id == a }?.frame
            if !Contract.near(read, got) {
                fail("the scan reads back the size a window kept", "frame \(Contract.show(got)) scan \(Contract.show(read))")
            }
            subject.move(a, to: target, from: got, behavior: Behaviors())
            _ = host.wait(until: host.now + 0.25) { Contract.near(subject.frame(a), target) }
        }
        if let b = host.open() {
            _ = host.wait(until: host.now + 1) { subject.scan(screens, full: true).windows.contains { $0.id == b } }
            let pair = subject.scan(screens, full: true).windows.filter { $0.id == a || $0.id == b }
            if pair.count != 2 || pair.filter(\.isMain).count != 1 {
                fail("a second window of the same app lists main once",
                     "listed \(pair.count), main \(pair.filter(\.isMain).count)")
            }
        }
        if let r = host.openRefusing() {
            _ = host.wait(until: host.now + 1) { subject.scan(screens, full: true).windows.contains { $0.id == r } }
            let before = subject.frame(r)
            subject.move(r, to: target, from: before, behavior: Behaviors())
            if !subject.refused.contains(r) {
                fail("a refused move lands in refused", "refused \(subject.refused.sorted())")
            }
            if subject.frame(r) != before {
                fail("a refused move leaves the frame", "before \(Contract.show(before)) after \(Contract.show(subject.frame(r)))")
            }
        }
        subject.minimize(a)
        if !host.wait(until: host.now + 1, { !subject.scan(screens, full: true).windows.contains { $0.id == a } }) {
            fail("minimize removes the window from scan within 1 s", "still listed")
        }
        subject.close(a)
        if !host.wait(until: host.now + 1, { !subject.alive().contains(a) }) {
            fail("close removes the window from alive within 1 s", "still alive")
        }
        return out
    }
}
