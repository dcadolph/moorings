import MooringsCore
import MooringsEngine

// ScreenSourceContract checks that a ScreenSource lists at least one display with sane frames and gives
// the same quirks and display set key for the same screens.
public enum ScreenSourceContract {
    // run checks subject and returns every rule it broke.
    public static func run(_ subject: ScreenSource, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        let screens = subject.current()
        if screens.full.isEmpty {
            fail("current lists at least one screen", "none listed")
            return out
        }
        if screens.usable.count != screens.full.count {
            fail("every screen has a usable frame", "full \(screens.full.count) usable \(screens.usable.count)")
        }
        for (i, full) in screens.full.enumerated() {
            if full.w <= 0 || full.h <= 0 {
                fail("every full frame is non-empty", "screen \(i) \(full)")
            }
            guard i < screens.usable.count else { continue }
            let usable = screens.usable[i]
            if usable.w <= 0 || usable.h <= 0 {
                fail("every usable frame is non-empty", "screen \(i) \(usable)")
            }
            let inside =
                usable.x >= full.x - 1 && usable.y >= full.y - 1 && usable.x + usable.w <= full.x + full.w + 1
                && usable.y + usable.h <= full.y + full.h + 1
            if !inside {
                fail(
                    "a usable frame lies inside its full frame within 1 px", "screen \(i) full \(full) usable \(usable)"
                )
            }
        }
        let first = subject.quirks(screens)
        let second = subject.quirks(screens)
        if first != second {
            fail("quirks gives the same answer for the same screens", "first \(first) second \(second)")
        }
        let keyA = subject.displaySetKey(screens)
        let keyB = subject.displaySetKey(screens)
        if keyA != keyB {
            fail("displaySetKey gives the same key for the same screens", "first \(keyA) second \(keyB)")
        }
        return out
    }
}
