import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// fakeHost builds a fake store, clock and host over the fake ultrawide.
func fakeHost() -> (FakeWindows, FakeClock, FakeHost) {
    let windows = FakeWindows()
    let clock = FakeClock()
    return (windows, clock, FakeHost(windows: windows, clock: clock, screens: FakeScreens.ultrawide()))
}

// The fake window store keeps every WindowStore rule.
@Test func testWindowStoreContractOnFake() {
    let (windows, _, host) = fakeHost()
    let failures = WindowStoreContract.run(windows, host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// A store that ignores the minimum breaks the minimum rule, by name.
@Test func testWindowStoreContractCatchesMinimum() {
    let (windows, _, host) = fakeHost()
    windows.ignoresMinimum = true
    let failures = WindowStoreContract.run(windows, host: host)
    #expect(failures.map(\.rule) == ["a move below the minimum keeps the minimum"])
}

// The fake overlay keeps every OverlayView rule.
@Test func testOverlayContractOnFake() {
    let (windows, _, host) = fakeHost()
    let failures = OverlayContract.run(FakeOverlay(), store: windows, host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// The fake badge keeps every BadgeView rule.
@Test func testBadgeContractOnFake() {
    let (windows, _, host) = fakeHost()
    let failures = BadgeContract.run(FakeBadge(), store: windows, host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// StuckBadge is a BadgeView that keeps its first mark, for the badge contract's negative control.
final class StuckBadge: BadgeView {
    // shown is the first mark shown, nil when hidden.
    private(set) var shown: BadgeMark?

    // show keeps the mark only when none is shown.
    func show(_ count: Int, at front: Frame, palette: Palette) {
        shown = shown ?? BadgeMark(count: count, front: front)
    }

    // hide clears the mark.
    func hide() {
        shown = nil
    }
}

// A badge that does not move on a second show breaks that rule, by name.
@Test func testBadgeContractCatchesStuck() {
    let (windows, _, host) = fakeHost()
    let failures = BadgeContract.run(StuckBadge(), store: windows, host: host)
    #expect(failures.map(\.rule) == ["a second show moves the badge"])
}

// The fake grid keeps every GridView rule.
@Test func testGridContractOnFake() {
    let (windows, _, host) = fakeHost()
    let failures = GridContract.run(FakeGrid(), store: windows, host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// StuckGrid is a GridView that keeps its first mark and is never hit, for the grid contract's
// negative control.
final class StuckGrid: GridView {
    // onMouse is never called.
    var onMouse: ((GridMouse, Point) -> Void)?
    // shown is the first mark shown, nil when hidden.
    private(set) var shown: GridMark?

    // show keeps the mark only when none is shown.
    func show(_ grid: OverlayGrid, in area: Frame, gap: Double, style: FootprintStyle, palette: Palette) {
        shown = shown ?? GridMark(grid: grid, area: area)
    }

    // hide clears the mark.
    func hide() {
        shown = nil
    }

    // contains is always false.
    func contains(_ p: Point) -> Bool {
        false
    }
}

// A grid that does not repaint and is never hit breaks those two rules, by name.
@Test func testGridContractCatchesStuck() {
    let (windows, _, host) = fakeHost()
    let failures = GridContract.run(StuckGrid(), store: windows, host: host)
    #expect(failures.map(\.rule) == ["a second show repaints the span", "contains is true at the middle of the shown area"])
}

// The fake notifier keeps every Notifier rule.
@Test func testNotifierContractOnFake() {
    let (windows, _, host) = fakeHost()
    let failures = NotifierContract.run(FakeNotifier(), store: windows, host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// The fake scheduler and clock keep every Scheduler and Clock rule.
@Test func testSchedulerContractOnFake() {
    let (_, clock, host) = fakeHost()
    let failures = SchedulerContract.run(FakeScheduler(clock: clock), clock: clock, host: host)
    #expect(failures.isEmpty, "\(failures)")
}
