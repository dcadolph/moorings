import MooringsCore
import MooringsEngine

// PointerContract checks that a Pointer reads a position on a screen, warps within a point, and
// reports no button while the host holds none.
public enum PointerContract {
    // run checks subject while host runs the platform and returns every rule it broke. It puts the
    // pointer back where it found it.
    public static func run(_ subject: Pointer, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        let screens = host.screens()
        let start = subject.position
        defer { subject.warp(start) }
        let on = screens.full.contains { f in
            start.x >= f.x && start.x <= f.x + f.w && start.y >= f.y && start.y <= f.y + f.h
        }
        if !on {
            fail("position lies on a screen", "at \(start.x), \(start.y)")
        }
        let area = screens.usable[0]
        let target = Point(x: (area.x + area.w / 2).rounded(), y: (area.y + area.h / 2).rounded())
        subject.warp(target)
        let near = { abs(subject.position.x - target.x) <= 1 && abs(subject.position.y - target.y) <= 1 }
        if !host.wait(until: host.now + 0.25, near) {
            fail(
                "after warp the position is within 1 px inside 250 ms",
                "asked \(target.x), \(target.y) got \(subject.position.x), \(subject.position.y)")
        }
        if subject.buttonDown {
            fail("buttonDown is false while the host holds nothing", "down")
        }
        return out
    }
}
