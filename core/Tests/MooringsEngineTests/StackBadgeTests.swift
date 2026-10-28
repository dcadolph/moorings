import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// stackFrames is a stack of three windows front to back, the front one at 1020,320 and the others
// within the default reach of its corner.
let stackFrames = [
    Frame(x: 1020, y: 320, w: 700, h: 500),
    Frame(x: 1015, y: 315, w: 700, h: 500),
    Frame(x: 1010, y: 310, w: 700, h: 500),
]

// BadgeRig is a stack badge with its choice on, on an engine over fakes, that counts how often it
// reads the windows.
final class BadgeRig {
    // view is the fake badge view.
    let view = FakeBadge()
    // windows holds the stacked windows.
    let windows = FakeWindows()
    // clock runs the badge's ticks.
    let clock = FakeClock()
    // pointer is where each tick reads the pointer.
    let pointer = FakePointer()
    // engine builds the badge.
    let engine: Engine
    // badge is the stack badge under test.
    let badge: StackBadge

    // init builds the rig with a window at each of frames, front to back, and the routed features.
    init(_ frames: [Frame] = stackFrames, features: Engine.Features = .all) {
        var c = Choices()
        c.stacking.badge = true
        for f in frames.reversed() {
            windows.add(bundle: "com.example.pad", frame: f)
        }
        engine = newTestEngine(
            newTestPlatform(
                windows: windows, screens: FakeScreens.ultrawide(), clock: clock, store: FakeStore(c),
                pointer: pointer, badge: view),
            features: features)
        badge = engine.badge
        badge.sync()
    }

    // reads counts the window reads.
    var reads: Int { windows.calls.filter { $0 == .scan(full: false) }.count }

    // tick puts the pointer at x, y and runs one tick.
    func tick(_ x: Double, _ y: Double, down: Bool = false) {
        pointer.position = Point(x: x, y: y)
        pointer.buttonDown = down
        clock.advance(by: Pace.pollSeconds)
    }
}

// Test 0: A pointer resting at the front window's corner shows the stack's count on that window,
// after one tick of rest, from one frame read.
@Test func testStackBadgeShowsOnRest() {
    let rig = BadgeRig()
    rig.tick(1030, 330)
    #expect(rig.view.shown == nil && rig.reads == 0)
    rig.tick(1030, 330)
    #expect(rig.view.shown == BadgeMark(count: 3, front: stackFrames[0]))
    rig.tick(1031, 330)
    rig.tick(1031, 331)
    #expect(rig.reads == 1, "one read per rest")
}

// Test 1: A move past restMove hides the badge, and the next rest reads the frames again.
@Test func testStackBadgeHidesOnMove() {
    let rig = BadgeRig()
    rig.tick(1030, 330)
    rig.tick(1030, 330)
    rig.tick(1030 + StackBadge.restMove + 1, 330)
    #expect(rig.view.shown == nil)
    rig.tick(1030 + StackBadge.restMove + 1, 330)
    #expect(rig.view.shown?.count == 3 && rig.reads == 2)
}

// Test 2: A mouse button down hides the badge and restarts the rest.
@Test func testStackBadgeHidesOnButton() {
    let rig = BadgeRig()
    rig.tick(1030, 330)
    rig.tick(1030, 330)
    rig.tick(1030, 330, down: true)
    #expect(rig.view.shown == nil)
    rig.tick(1030, 330)
    #expect(rig.view.shown == nil, "the first tick after release starts a rest")
    rig.tick(1030, 330)
    #expect(rig.view.shown?.count == 3)
}

// Test 3: A rest away from any window's corner shows nothing.
@Test func testStackBadgeNothingOffCorner() {
    let rig = BadgeRig()
    rig.tick(1400, 600)
    rig.tick(1400, 600)
    #expect(rig.view.shown == nil && rig.reads == 1)
}

// Test 4: A lone window at the corner shows no badge.
@Test func testStackBadgeLoneWindow() {
    let rig = BadgeRig([stackFrames[0]])
    rig.tick(1030, 330)
    rig.tick(1030, 330)
    #expect(rig.view.shown == nil)
}

// Test 5: The badge ticks only while its choice is on and the platform declares a badge, and a save
// that turns the choice off stops the ticks and hides it.
@Test func testStackBadgeSync() {
    let rig = BadgeRig()
    #expect(rig.badge.running)
    rig.tick(1030, 330)
    rig.tick(1030, 330)
    #expect(rig.view.shown?.count == 3)
    rig.engine.anchors.choices.stacking.badge = false
    rig.engine.save()
    #expect(!rig.badge.running && rig.view.shown == nil)
    let none = BadgeRig(features: .all.subtracting(.badge))
    #expect(!none.badge.running)
    none.tick(1030, 330)
    none.tick(1030, 330)
    #expect(none.view.shown == nil && none.reads == 0)
}
