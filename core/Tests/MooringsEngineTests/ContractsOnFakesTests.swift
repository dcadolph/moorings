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
