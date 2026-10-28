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

// BadgeRig is a stack badge on a fake view that counts how often it reads the window frames.
final class BadgeRig {
    // view is the fake badge view.
    let view = FakeBadge()
    // badge is the stack badge under test.
    let badge: StackBadge
    // reads counts the frame reads.
    var reads = 0
    // frames is what a frame read returns.
    var frames = stackFrames

    // init builds the rig.
    init() {
        badge = StackBadge(view: view)
    }

    // tick runs one update with the pointer at x, y.
    func tick(_ x: Double, _ y: Double, down: Bool = false) {
        badge.update(
            pointer: Point(x: x, y: y), buttonDown: down,
            frames: {
                self.reads += 1; return self.frames
            },
            palette: .harbor, choices: StackChoices(), gap: 0)
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
    let rig = BadgeRig()
    rig.frames = [stackFrames[0]]
    rig.tick(1030, 330)
    rig.tick(1030, 330)
    #expect(rig.view.shown == nil)
}
