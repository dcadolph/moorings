import Foundation
import Testing

@testable import MooringsCore

// PaceCase is one call to Pace.next and the time it must return.
struct PaceCase: Sendable {
    // Now is when the pass ran.
    var Now: Double
    // Woke is when the last event came.
    var Woke: Double
    // Busy reports whether something pending needs a look without an event.
    var Busy = false
    // Deadlines lists the times a pass decides differently.
    var Deadlines: [Double] = []
    // WantNext is the time of the next pass, nil when none is due until an event.
    var WantNext: Double?
}

// paceCases covers the settle window, rest, busy and deadlines.
let paceCases: [PaceCase] = [
    // Test 0: Right after an event, passes run every pollSeconds.
    PaceCase(Now: 100, Woke: 100, WantNext: 100.25),
    // Test 1: Still inside the settle window, deadlines and busy do not slow it down.
    PaceCase(Now: 101.9, Woke: 100, Busy: true, Deadlines: [150], WantNext: 102.15),
    // Test 2: Settled with nothing pending, no pass is due.
    PaceCase(Now: 102, Woke: 100, WantNext: nil),
    // Test 3: Settled and busy, passes run every busySeconds.
    PaceCase(Now: 200, Woke: 100, Busy: true, WantNext: 202),
    // Test 4: Settled with a deadline, the pass runs just after it.
    PaceCase(Now: 200, Woke: 100, Deadlines: [230], WantNext: 230.05),
    // Test 5: The earliest of several deadlines wins.
    PaceCase(Now: 200, Woke: 100, Deadlines: [260, 210, 230], WantNext: 210.05),
    // Test 6: A deadline before the next busy pass wins over it.
    PaceCase(Now: 200, Woke: 100, Busy: true, Deadlines: [201], WantNext: 201.05),
    // Test 7: Busy wins over a later deadline.
    PaceCase(Now: 200, Woke: 100, Busy: true, Deadlines: [230], WantNext: 202),
    // Test 8: Spent deadlines never keep it awake.
    PaceCase(Now: 200, Woke: 100, Deadlines: [150, 200], WantNext: nil),
]

@Test(arguments: paceCases)
func testPaceNext(test: PaceCase) {
    let got = Pace.next(now: test.Now, woke: test.Woke, busy: test.Busy, deadlines: test.Deadlines)
    #expect(got == test.WantNext)
}

// Test 9: An app moorings opened leaves a deadline when its strip lapses, and none once lapsed.
@Test func testDeadlinesOpening() {
    let anchors = Anchors()
    var world = TestWorld()
    world.pass(anchors)
    #expect(anchors.deadlines().isEmpty)
    anchors.lock(.rightTop, iterm, now: world.clock)
    world.pass(anchors)
    #expect(anchors.deadlines() == [world.clock + Anchors.openSeconds])
    world.clock += 31
    world.pass(anchors)
    #expect(anchors.deadlines().isEmpty)
}

// Test 10: An app whose window showed leaves no deadline.
@Test func testDeadlinesShown() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    anchors.launch(now: world.clock)
    world.pass(anchors)
    #expect(anchors.deadlines().isEmpty)
}

// Test 11: A window put on hold for fighting its place leaves a deadline when the hold ends, and
// the pass at that deadline places it.
@Test func testDeadlinesHold() throws {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let w = world.add("com.apple.Safari", Frame(x: 0, y: 25, w: 800, h: 600))
    world.pass(anchors)
    for _ in 0..<4 {
        world.set(w, Frame(x: 0, y: 25, w: 800, h: 600))
        world.clock += 1
        world.pass(anchors)
    }
    let due = try #require(anchors.deadlines().first)
    #expect(anchors.deadlines().count == 1 && due > world.clock)
    world.clock = due
    world.pass(anchors)
    #expect(world.frame(w).x == 512)
    #expect(anchors.deadlines().isEmpty)
}

// Test 12: A focused window macOS zooms across both strips goes back to the channel on every zoom,
// and is never put on hold for it.
@Test func testZoomFillsChannel() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let w = world.add("com.google.Chrome", Frame(x: 600, y: 25, w: 2000, h: 1415))
    world.focused = w
    world.pass(anchors)
    for _ in 0..<6 {
        world.clock += 1
        world.set(w, wide)
        world.pass(anchors)
        #expect(world.frame(w) == Frame(x: 512, y: 25, w: 2304, h: 1415))
    }
    #expect(anchors.deadlines().isEmpty)
}

// Test 13: A window that is not focused and keeps spreading across both strips is still put on hold.
@Test func testSpreadUnfocusedHolds() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let w = world.add("com.google.Chrome", Frame(x: 600, y: 25, w: 2000, h: 1415))
    world.pass(anchors)
    for _ in 0..<5 {
        world.clock += 1
        world.set(w, wide)
        world.pass(anchors)
    }
    #expect(world.frame(w) == wide)
    #expect(anchors.deadlines().count == 1)
}
