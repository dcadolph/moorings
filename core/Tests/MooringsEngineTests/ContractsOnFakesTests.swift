import Foundation

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
    #expect(
        failures.map(\.rule) == ["a second show repaints the span", "contains is true at the middle of the shown area"])
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

// The fake pointer keeps every Pointer rule and stops tracking when told.
@Test func testPointerContractOnFake() {
    let (_, _, host) = fakeHost()
    let pointer = FakePointer()
    let failures = PointerContract.run(pointer, host: host)
    #expect(failures.isEmpty, "\(failures)")
    #expect(pointer.tracker == nil && pointer.tracks == [true, false])
}

// A pointer that reports the primary button with no button held breaks both primary rules, by name.
@Test func testPointerContractCatchesPrimaryWithoutButton() {
    let (_, _, host) = fakeHost()
    let pointer = FakePointer()
    pointer.primaryDown = true
    let failures = PointerContract.run(pointer, host: host)
    #expect(
        failures.map(\.rule) == [
            "primaryDown is false while the host holds nothing", "primaryDown is never true while buttonDown is false",
        ])
}

// The fake keys keep every Keys rule, with the host pressing through them.
@Test func testKeysContractOnFake() {
    let (_, _, host) = fakeHost()
    let keys = FakeKeys()
    host.keys = keys
    let failures = KeysContract.run(keys, host: host, actions: { keys.actions })
    #expect(failures.isEmpty, "\(failures)")
    #expect(keys.actions == ["contract-bound"] && keys.bound.isEmpty)
}

// StickyKeys is a Keys that ignores a bind of an empty map, for the keys contract's negative control.
final class StickyKeys: Keys {
    // inner is the fake that holds the bindings.
    let inner = FakeKeys()

    // shortcutsOn is the inner keys'.
    var shortcutsOn: Bool { inner.shortcutsOn }

    // bind passes on every map but an empty one.
    func bind(_ map: [String: Shortcut]) {
        if !map.isEmpty {
            inner.bind(map)
        }
    }

    // grab grabs on the inner keys.
    func grab(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        inner.grab(keys, handler)
    }

    // ungrab lets the inner keys go.
    func ungrab() {
        inner.ungrab()
    }

    // claim claims on the inner keys.
    func claim(_ keys: [GrabKey], _ handler: @escaping (String) -> Void) -> Int {
        inner.claim(keys, handler)
    }

    // unclaim lets the inner claim go.
    func unclaim() {
        inner.unclaim()
    }

    // spell spells through the inner keys.
    func spell(_ s: Shortcut) -> String {
        inner.spell(s)
    }
}

// Keys that keep a shortcut after an empty bind break that rule, by name.
@Test func testKeysContractCatchesStickyBind() {
    let (_, _, host) = fakeHost()
    let keys = StickyKeys()
    host.keys = keys.inner
    let failures = KeysContract.run(keys, host: host, actions: { keys.inner.actions })
    #expect(failures.map(\.rule) == ["bind of an empty map after a bind leaves no shortcut delivering"])
}

// The fake apps keep every Apps rule.
@Test func testAppsContractOnFake() {
    let (windows, _, host) = fakeHost()
    let failures = AppsContract.run(FakeApps(windows: windows), store: windows, host: host)
    #expect(failures.isEmpty, "\(failures)")
    #expect(windows.windows.isEmpty, "the suite closes the window it opened")
}

// The fake log keeps every Log rule.
@Test func testLogContractOnFake() {
    let (_, _, host) = fakeHost()
    let failures = LogContract.run(FakeLog(), host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// The fake timers keep every Timers rule and every Scheduler rule on what they hand out.
@Test func testTimersContractOnFake() {
    let (_, clock, host) = fakeHost()
    let failures = TimersContract.run(FakeTimers(clock: clock), clock: clock, host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// The fake events keep every EventSource rule.
@Test func testEventSourceContractOnFake() {
    let (windows, _, host) = fakeHost()
    let failures = EventSourceContract.run(FakeEvents(windows: windows), store: windows, host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// DroppingEvents is an EventSource that loses every destroyed event, for the events contract's
// negative control.
final class DroppingEvents: EventSource {
    // inner is the source whose events pass through.
    private let inner: FakeEvents

    // init wraps inner.
    init(_ inner: FakeEvents) {
        self.inner = inner
    }

    // waiting is the inner source's.
    var waiting: Bool { inner.waiting }

    // start passes on every event but destroyed.
    func start(_ deliver: @escaping (WindowEvent) -> Void) {
        inner.start { event in
            if case .destroyed = event { return }
            deliver(event)
        }
    }

    // stop stops the inner source.
    func stop() {
        inner.stop()
    }

    // watch passes the scan on.
    func watch(_ scan: Scan) {
        inner.watch(scan)
    }
}

// A source that drops destroyed breaks that rule, by name.
@Test func testEventSourceContractCatchesDroppedDestroyed() {
    let (windows, _, host) = fakeHost()
    let failures = EventSourceContract.run(DroppingEvents(FakeEvents(windows: windows)), store: windows, host: host)
    #expect(failures.map(\.rule) == ["a host close delivers destroyed within 1 s"])
}

// The fake screens keep every ScreenSource rule.
@Test func testScreenSourceContractOnFake() {
    let (_, _, host) = fakeHost()
    let failures = ScreenSourceContract.run(FakeScreens.ultrawide(), host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// The fake store keeps every ChoicesStore rule, with the host rewriting it from outside.
@Test func testChoicesStoreContractOnFake() {
    let (_, _, host) = fakeHost()
    let store = FakeStore()
    host.store = store
    let failures = ChoicesStoreContract.run(store, host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// DeafStore is a ChoicesStore that never reports a change, for the store contract's negative control.
final class DeafStore: ChoicesStore {
    // inner is the fake that holds the choices.
    let inner = FakeStore()

    // load loads from the inner store.
    func load() -> Loaded {
        inner.load()
    }

    // save saves to the inner store.
    func save(_ choices: Choices) throws {
        try inner.save(choices)
    }

    // changed is always false.
    func changed() -> Bool {
        false
    }
}

// A store that misses a rewrite from outside breaks that rule, by name.
@Test func testChoicesStoreContractCatchesMissedRewrite() {
    let (_, _, host) = fakeHost()
    let store = DeafStore()
    host.store = store.inner
    let failures = ChoicesStoreContract.run(store, host: host)
    #expect(failures.map(\.rule) == ["changed is true after the host rewrites the choices"])
}

// The fake clock keeps every Clock rule.
@Test func testClockContractOnFake() {
    let (_, clock, host) = fakeHost()
    let failures = ClockContract.run(clock, host: host)
    #expect(failures.isEmpty, "\(failures)")
}

// BackwardClock is a Clock whose first three reads run backward across the contract's 50 ms waits and
// whose later reads follow the host, for the clock contract's negative control.
final class BackwardClock: Clock {
    // host is the host whose time the clock follows.
    private let host: ContractHost
    // lags is how far each of the first reads sits from the host's time.
    private let lags = [-0.02, 0.031, 0.082]
    // reads counts the reads so far.
    private var reads = 0

    // init builds a clock that follows host.
    init(host: ContractHost) {
        self.host = host
    }

    // now is the host's time less the lag of this read, none after the first three.
    var now: Double {
        defer { reads += 1 }
        return host.now - (reads < lags.count ? lags[reads] : 0)
    }
}

// A clock that steps backward breaks the monotonic rule, by name.
@Test func testClockContractCatchesBackward() {
    let (_, _, host) = fakeHost()
    let failures = ClockContract.run(BackwardClock(host: host), host: host)
    #expect(failures.map(\.rule) == ["the clock is monotonic"])
}

// A store that keeps a minimized window out of reach of close breaks that rule, by name.
@Test func testWindowStoreContractCatchesForgottenMinimized() {
    let (windows, _, host) = fakeHost()
    windows.forgetsMinimized = true
    let failures = WindowStoreContract.run(windows, host: host)
    #expect(failures.map(\.rule) == ["a listed window stays actionable until it is gone"])
}

// KeepStore is a ChoicesStore that leaves a payload it cannot read in place, for the corrupt-payload
// rule's negative control.
final class KeepStore: ChoicesStore {
    // inner is the fake that holds the choices.
    let inner = FakeStore()
    // payload is the spoiled payload, kept in place.
    var payload: Data?

    // load falls back on a spoiled payload every time and never moves it aside.
    func load() -> Loaded {
        if let payload {
            return Choices.decode(payload)
        }
        return inner.load()
    }

    // save saves to the inner store and drops the payload.
    func save(_ choices: Choices) throws {
        payload = nil
        try inner.save(choices)
    }

    // changed asks the inner store.
    func changed() -> Bool {
        inner.changed()
    }
}

// KeepHost is a FakeHost that spoils a KeepStore.
final class KeepHost: ContractHost {
    // base is the fake host the rest is asked of.
    let base: FakeHost
    // store is the store spoilChoices writes to.
    let store: KeepStore

    // init builds a host over base and store.
    init(base: FakeHost, store: KeepStore) {
        self.base = base
        self.store = store
    }

    // minimum is the base host's.
    var minimum: (w: Double, h: Double)? { base.minimum }
    // now is the base host's clock.
    var now: Double { base.now }

    // screens returns the base host's displays.
    func screens() -> Screens {
        base.screens()
    }

    // open opens a base host window.
    func open() -> WindowID? {
        base.open()
    }

    // openRefusing opens a base host window that refuses moves.
    func openRefusing() -> WindowID? {
        base.openRefusing()
    }

    // wait waits on the base host.
    func wait(until deadline: Double, _ done: () -> Bool) -> Bool {
        base.wait(until: deadline, done)
    }

    // finish closes the base host's windows.
    func finish() {
        base.finish()
    }

    // spoilChoices keeps payload in the store.
    func spoilChoices(_ payload: Data) -> Bool {
        store.payload = payload
        return true
    }

    // choicesAside is nil: the store moves nothing aside.
    func choicesAside() -> Data? {
        nil
    }
}

// A store that leaves an unreadable payload in place breaks the corrupt-payload rule, by name.
@Test func testChoicesStoreContractCatchesKeptPayload() {
    let (_, _, base) = fakeHost()
    let store = KeepStore()
    let failures = ChoicesStoreContract.run(store, host: KeepHost(base: base, store: store))
    #expect(
        Set(failures.map(\.rule)) == ["a corrupt payload loads the defaults with a reason and moves aside"],
        "\(failures)")
}
