import MooringsCore
import MooringsEngine

// GridContract checks that a GridView shows, repaints, hit tests and hides the grid without taking
// the focus from the window under it.
public enum GridContract {
    // run checks subject over a focused host window read through store and returns every rule it broke.
    public static func run(_ subject: GridView, store: WindowStore, host: ContractHost) -> [ContractFailure] {
        var out: [ContractFailure] = []
        defer {
            subject.hide()
            host.finish()
        }
        let fail = { (rule: String, detail: String) in out.append(ContractFailure(rule: rule, detail: detail)) }
        guard let a = Contract.focus(store, host, &out) else { return out }
        let screens = host.screens()
        let u = screens.usable[0]
        let area = Frame(x: u.x + 20, y: u.y + 20, w: 600, h: 400)
        let first = GridMark(grid: OverlayGrid(cols: 3, rows: 2, at: Point(x: area.x + 10, y: area.y + 10), in: area),
                             area: area)
        subject.show(first.grid, in: area, gap: 0, style: FootprintStyle(), palette: .harbor)
        if subject.shown != first {
            fail("show then shown equals the mark", "asked \(show(first)) shown \(show(subject.shown))")
        }
        let second = GridMark(grid: first.grid.moved(.right), area: area)
        subject.show(second.grid, in: area, gap: 0, style: FootprintStyle(), palette: .harbor)
        if subject.shown != second {
            fail("a second show repaints the span", "asked \(show(second)) shown \(show(subject.shown))")
        }
        let inside = Point(x: area.x + area.w / 2, y: area.y + area.h / 2)
        let outside = Point(x: area.x + area.w + 10, y: area.y + area.h / 2)
        if !subject.contains(inside) {
            fail("contains is true at the middle of the shown area", "false at \(inside)")
        }
        if subject.contains(outside) {
            fail("contains is false 10 points past the shown area", "true at \(outside)")
        }
        _ = host.wait(until: host.now + 0.25) { false }
        if store.scan(screens, full: true).focused?.id != a {
            fail("the grid never takes focus from the host window", "focus moved off \(a)")
        }
        subject.hide()
        if subject.shown != nil {
            fail("hide clears shown", "shown \(show(subject.shown))")
        }
        if subject.contains(inside) {
            fail("contains is false once hidden", "true at \(inside)")
        }
        return out
    }

    // show writes a mark, or none, for a failure detail.
    private static func show(_ m: GridMark?) -> String {
        m.map { "\($0.grid.c0)-\($0.grid.c1)x\($0.grid.r0)-\($0.grid.r1) over \($0.area)" } ?? "none"
    }
}
