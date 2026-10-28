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
