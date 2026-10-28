import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// near reports whether two frames agree within one point on every edge.
func near(_ a: Frame?, _ b: Frame?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return abs(a.x - b.x) <= 1 && abs(a.y - b.y) <= 1 && abs(a.w - b.w) <= 1 && abs(a.h - b.h) <= 1
}

// A move on a cooperative window reads back as the frame asked for.
@Test func testFakeWindowsMoveReadsBack() {
    let store = FakeWindows()
    let id = store.add(bundle: "a", frame: Frame(x: 100, y: 100, w: 400, h: 300))
    let to = Frame(x: 0, y: 25, w: 860, h: 1415)
    store.move(id, to: to, from: nil, behavior: Behaviors())
    #expect(near(store.frame(id), to))
    #expect(store.calls == [.move(id, to, from: nil)])
}

// A move below the minimum size keeps the minimum.
@Test func testFakeWindowsKeepsMinimum() {
    let store = FakeWindows()
    let id = store.add(bundle: "a", frame: Frame(x: 100, y: 100, w: 900, h: 700), minW: 800, minH: 600)
    store.move(id, to: Frame(x: 0, y: 25, w: 500, h: 400), from: nil, behavior: Behaviors())
    #expect(store.frame(id) == Frame(x: 0, y: 25, w: 800, h: 600))
    store.resize(id, w: 10, h: 10)
    #expect(store.frame(id) == Frame(x: 0, y: 25, w: 800, h: 600))
}

// Insets grow the landed rect the way an uncorrected invisible border does.
@Test func testFakeWindowsInsetsGrowLandedRect() {
    let store = FakeWindows()
    let id = store.add(
        bundle: "a", frame: Frame(x: 100, y: 100, w: 400, h: 300),
        insets: Insets(left: 7, top: 0, right: 7, bottom: 7))
    store.move(id, to: Frame(x: 0, y: 25, w: 860, h: 1415), from: nil, behavior: Behaviors())
    #expect(store.frame(id) == Frame(x: -7, y: 25, w: 874, h: 1422))
}

// A refused move leaves the frame and lists the window as refused.
@Test func testFakeWindowsRefusedLeavesFrame() {
    let store = FakeWindows()
    let start = Frame(x: 100, y: 100, w: 400, h: 300)
    let id = store.add(bundle: "a", frame: start, refuses: true)
    store.move(id, to: Frame(x: 0, y: 25, w: 860, h: 1415), from: start, behavior: Behaviors())
    #expect(store.frame(id) == start)
    #expect(store.refused == [id])
}

// Raise focuses and fronts, minimize leaves the scan, and close leaves alive.
@Test func testFakeWindowsRaiseMinimizeClose() {
    let store = FakeWindows()
    let screens = FakeScreens.ultrawide().current()
    let a = store.add(bundle: "a", frame: Frame(x: 100, y: 100, w: 400, h: 300))
    let b = store.add(bundle: "b", frame: Frame(x: 600, y: 100, w: 400, h: 300), focus: true)
    #expect(store.scan(screens, full: true).windows.map(\.id) == [b, a])
    store.raise(a)
    let scan = store.scan(screens, full: true)
    #expect(scan.windows.map(\.id) == [a, b])
    #expect(scan.focused?.id == a)
    store.minimize(a)
    #expect(store.scan(screens, full: true).windows.map(\.id) == [b])
    #expect(store.alive() == [a, b])
    store.close(b)
    #expect(store.alive() == [a])
}

// The scheduler runs its work once, at or after the time asked.
@Test func testFakeSchedulerRunsOnceWhenDue() {
    let clock = FakeClock()
    let s = FakeScheduler(clock: clock)
    let seen: any Clock = clock
    var ran: [Double] = []
    s.schedule(at: 2) { ran.append(seen.now) }
    clock.advance(to: 1.9)
    #expect(ran.isEmpty)
    clock.advance(to: 5)
    #expect(ran == [2])
    clock.advance(to: 10)
    #expect(ran == [2])
    #expect(s.runs == 1)
}

// Cancel stops the pending work.
@Test func testFakeSchedulerCancel() {
    let clock = FakeClock()
    let s = FakeScheduler(clock: clock)
    var ran = false
    s.schedule(at: 1) { ran = true }
    s.cancel()
    clock.advance(to: 5)
    #expect(!ran)
}

// A second schedule replaces the first.
@Test func testFakeSchedulerReplaces() {
    let clock = FakeClock()
    let s = FakeScheduler(clock: clock)
    var ran: [String] = []
    s.schedule(at: 1) { ran.append("first") }
    s.schedule(at: 3) { ran.append("second") }
    clock.advance(to: 5)
    #expect(ran == ["second"])
}

// Work that schedules more work inside the span runs again at its own time.
@Test func testFakeSchedulerChainsInsideSpan() {
    let clock = FakeClock()
    let s = FakeScheduler(clock: clock)
    var ran: [Double] = []
    func tick() {
        ran.append(clock.now)
        if ran.count < 3 {
            s.schedule(at: clock.now + 1, tick)
        }
    }
    s.schedule(at: 1, tick)
    clock.advance(to: 10)
    #expect(ran == [1, 2, 3])
    #expect(clock.now == 10)
}

// The store loads the initial choices, then the last saved ones, and throws when failing.
@Test func testFakeStore() throws {
    var c = Choices()
    c.paused = true
    let store = FakeStore()
    #expect(store.load() == Choices())
    try store.save(c)
    #expect(store.load() == c)
    store.failing = true
    #expect(throws: FakeStore.FakeError.self) { try store.save(Choices()) }
    #expect(store.saves == 1)
}

// The overlay shows, moves and hides.
@Test func testFakeOverlay() {
    let o = FakeOverlay()
    let a = Frame(x: 0, y: 25, w: 860, h: 1415)
    let b = Frame(x: 860, y: 25, w: 860, h: 1415)
    o.show(a, style: FootprintStyle(), palette: .harbor)
    o.show(b, style: FootprintStyle(), palette: .harbor)
    #expect(o.shown == b)
    o.hide()
    #expect(o.shown == nil)
    #expect(o.calls == [.show(a), .show(b), .hide])
}
