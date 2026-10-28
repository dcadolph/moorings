import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// DragRig is a follower on fakes over one 3440x1440 ultrawide with nothing anchored.
@MainActor
final class DragRig {
    // windows is the fake window store.
    let windows = FakeWindows()
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // overlay records the footprint.
    let overlay = FakeOverlay()
    // notifier records the messages.
    let notifier = FakeNotifier()
    // clock is the fake clock.
    let clock = FakeClock()
    // store keeps the choices the engine saves.
    let store: FakeStore
    // engine builds the follower and the action runner its drops apply through.
    let engine: Engine
    // anchors holds the choices.
    let anchors: Anchors
    // follower is the drag follower under test.
    let follower: DragFollower
    // applied records each zone action a drop ran, in order.
    var applied: [String] = []
    // id is the dragged window.
    let id: WindowID
    // start is where the dragged window begins.
    let start = Frame(x: 1200, y: 400, w: 800, h: 600)

    // init builds the rig with choices and a focused window at start.
    init(_ choices: Choices = Choices()) {
        store = FakeStore(choices)
        engine = newTestEngine(
            newTestPlatform(
                windows: windows, screens: screens, clock: clock, overlay: overlay, notifier: notifier, store: store))
        anchors = engine.anchors
        id = windows.add(bundle: "com.example.pad", frame: start, focus: true)
        follower = engine.drag
        engine.observers.dropped = { [unowned self] _, drop in
            if case let .zone(name) = drop {
                applied.append(name)
            }
        }
    }

    // changes counts the times a drop saved the choices.
    var changes: Int { store.saves }

    // frames lists the frames the fake preview gives on a usable area.
    static func frames(_ u: Frame) -> [String: Frame] {
        [
            "left-half": Frame(x: u.x, y: u.y, w: u.w / 2, h: u.h),
            "maximize": u,
            "first-third": Frame(x: u.x, y: u.y, w: u.w / 3, h: u.h),
            "first-two-thirds": Frame(x: u.x, y: u.y, w: u.w * 2 / 3, h: u.h),
            "center-third": Frame(x: u.x + u.w / 3, y: u.y, w: u.w / 3, h: u.h),
        ]
    }

    // drag presses at p0, moves the window with the pointer through points, and returns nothing.
    func drag(_ points: [Point], held: Modifiers = [], moveWindow: Bool = true) {
        follower.began(at: points[0])
        var last = points[0]
        for p in points.dropFirst() {
            if moveWindow {
                windows.nudge(
                    id,
                    to: Frame(
                        x: start.x + p.x - points[0].x, y: start.y + p.y - points[0].y,
                        w: start.w, h: start.h))
            }
            follower.moved(p, held: held)
            last = p
        }
        _ = last
    }

    // path returns points from a to b every 8 points of travel and a few past it.
    static func path(_ a: Point, _ b: Point) -> [Point] {
        let n = max(2, Int((abs(b.x - a.x) + abs(b.y - a.y)) / 8) + 2)
        return (0...n).map { i in
            let t = min(1, Double(i) / Double(n - 1))
            return Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        } + [b, b]
    }
}

// A drag that never moves the window shows nothing and drops nothing.
@Test @MainActor func testDragStillShowsNothing() {
    let rig = DragRig()
    rig.drag(DragRig.path(Point(x: 1600, y: 415), Point(x: 2, y: 700)), moveWindow: false)
    rig.follower.ended(held: [])
    #expect(rig.overlay.calls.allSatisfy { $0 == .hide })
    #expect(rig.applied.isEmpty)
}

// A drag that resizes the window shows nothing.
@Test @MainActor func testDragResizeShowsNothing() {
    let rig = DragRig()
    rig.follower.began(at: Point(x: 2000, y: 1000))
    for (i, p) in DragRig.path(Point(x: 2000, y: 1000), Point(x: 2, y: 700)).enumerated() {
        rig.windows.nudge(
            rig.id, to: Frame(x: rig.start.x, y: rig.start.y, w: rig.start.w + Double(i * 8), h: rig.start.h))
        rig.follower.moved(p, held: [])
    }
    rig.follower.ended(held: [])
    #expect(rig.overlay.shown == nil)
    #expect(rig.overlay.calls.allSatisfy { $0 == .hide })
    #expect(rig.applied.isEmpty)
}

// A move to the left edge shows the left half and the drop applies left-half on that screen.
@Test @MainActor func testDragLeftEdgeSnapsLeftHalf() {
    let rig = DragRig()
    rig.drag(DragRig.path(Point(x: 1600, y: 415), Point(x: 2, y: 700)))
    let u = rig.screens.screens.usable[0]
    #expect(rig.overlay.shown == Frame(x: u.x, y: u.y, w: u.w / 2, h: u.h))
    #expect(rig.follower.drop == .zone("left-half"))
    rig.follower.ended(held: [])
    #expect(rig.applied == ["left-half"])
    #expect(rig.windows.frame(rig.id) == Frame(x: u.x, y: u.y, w: u.w / 2, h: u.h))
    #expect(rig.overlay.shown == nil)
}

// The same drop with option over the left strip parks the app there and says so.
@Test @MainActor func testDragOptionParks() {
    let rig = DragRig()
    rig.drag(DragRig.path(Point(x: 1600, y: 415), Point(x: 2, y: 300)), held: .option)
    #expect(rig.follower.drop == .park("left-top"))
    #expect(rig.overlay.shown == rig.anchors.slotFrame(rig.screens.screens.usable[0], .leftTop))
    rig.follower.ended(held: .option)
    #expect(rig.anchors.choices.slots[.leftTop] == "com.example.pad")
    #expect(rig.notifier.notes.map(\.title) == ["com.example.pad anchored"])
    #expect(rig.changes == 1)
    #expect(rig.applied.isEmpty)
}

// The zone the drag came from carries across the band: a bottom drag from the first third into the
// middle shows two thirds, not the center third.
@Test @MainActor func testDragPrevKeepsZone() {
    let rig = DragRig()
    let y = 1438.0
    rig.drag(
        DragRig.path(Point(x: 1600, y: 415), Point(x: 500, y: y))
            + DragRig.path(Point(x: 500, y: y), Point(x: 1700, y: y)))
    #expect(rig.follower.drop == .zone("first-two-thirds"))
}

// Paused shows nothing and reads nothing.
@Test @MainActor func testDragPausedShowsNothing() {
    var c = Choices()
    c.paused = true
    let rig = DragRig(c)
    rig.drag(DragRig.path(Point(x: 1600, y: 415), Point(x: 2, y: 700)))
    rig.follower.ended(held: [])
    #expect(rig.overlay.shown == nil)
    #expect(rig.applied.isEmpty)
    #expect(!rig.windows.calls.contains(.scan(full: false)))
}

// A drop off every screen does nothing.
@Test @MainActor func testDragOffScreenDropsNothing() {
    let rig = DragRig()
    rig.drag(DragRig.path(Point(x: 1600, y: 415), Point(x: 3600, y: 700)))
    #expect(rig.overlay.shown == nil)
    rig.follower.ended(held: [])
    #expect(rig.applied.isEmpty)
}

// A window the store can no longer read ends the drag without a drop.
@Test @MainActor func testDragUnreadableEnds() {
    let rig = DragRig()
    rig.drag(DragRig.path(Point(x: 1600, y: 415), Point(x: 2, y: 700)))
    #expect(rig.follower.drop == .zone("left-half"))
    rig.windows.close(rig.id)
    rig.follower.ended(held: [])
    #expect(rig.applied.isEmpty)
}

// A platform that names the window and says it moves needs no travel to decide.
@Test @MainActor func testDragGivenWindowAndAnswer() {
    let rig = DragRig()
    var drops: [SnapDrop?] = []
    rig.engine.observers.dropped = { _, d in drops.append(d) }
    rig.follower.began(window: rig.id, moving: true)
    rig.windows.nudge(rig.id, to: Frame(x: 0, y: 400, w: 800, h: 600))
    rig.follower.moved(Point(x: 2, y: 700), held: [])
    #expect(rig.follower.drop == .zone("left-half"))
    rig.follower.ended(held: [])
    let u = rig.screens.screens.usable[0]
    #expect(rig.windows.frame(rig.id) == Frame(x: u.x, y: u.y, w: u.w / 2, h: u.h))
    #expect(drops == [.zone("left-half")])
}

// A platform that says the press sizes the window ends the drag at once.
@Test @MainActor func testDragGivenSizing() {
    let rig = DragRig()
    rig.follower.began(window: rig.id, moving: false)
    rig.follower.moved(Point(x: 2, y: 700), held: [])
    rig.follower.ended(held: [])
    #expect(rig.overlay.shown == nil)
    #expect(rig.applied.isEmpty)
}
