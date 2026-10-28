import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// TileRig is a tiler on fakes over one 3440x1440 ultrawide.
@MainActor
final class TileRig {
    // windows is the fake window store.
    let windows = FakeWindows()
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // notifier records the messages.
    let notifier = FakeNotifier()
    // clock is the fake clock.
    let clock = FakeClock(100)
    // pointer holds the primary button for the passes the engine runs.
    let pointer = FakePointer()
    // store keeps the choices the engine saves.
    let store: FakeStore
    // engine builds the tiler and runs the passes it asks for.
    let engine: Engine
    // anchors holds the choices.
    let anchors: Anchors
    // tiler is the tiler under test.
    let tiler: Tiler
    // moors counts the passes run.
    var moors = 0

    // init builds the rig with choices.
    init(_ choices: Choices = Choices()) {
        store = FakeStore(choices)
        engine = newTestEngine(
            newTestPlatform(
                windows: windows, screens: screens, clock: clock, notifier: notifier, store: store, pointer: pointer))
        anchors = engine.anchors
        tiler = engine.tiler
        engine.observers.passed = { [unowned self] _, _ in moors += 1 }
    }

    // changes counts the times the tiler saved the choices.
    var changes: Int { store.saves }

    // add opens a window at a spot of its own and returns its id.
    @discardableResult
    func add(focus: Bool = false) -> WindowID {
        let n = Double(windows.windows.count)
        return windows.add(
            bundle: "com.example.pad", frame: Frame(x: 200 + 40 * n, y: 200 + 40 * n, w: 700, h: 500),
            focus: focus)
    }

    // pass runs one tiling pass over what is on screen, as the pass loop does after a moor pass.
    func pass(mouseHeld: Bool = false) {
        tiler.pass(windows.scan(screens.screens, full: true).windows, screens: screens.screens, mouseHeld: mouseHeld)
    }

    // frames lists the frames of the windows with ids.
    func frames(_ ids: [WindowID]) -> [Frame] {
        ids.compactMap { windows.frame($0) }
    }

    // columns returns n equal columns across the whole usable area.
    func columns(_ n: Int) -> [Frame] {
        let u = screens.screens.usable[0]
        return (0..<n).map { k in Frame(x: u.x + u.w * Double(k) / Double(n), y: u.y, w: u.w / Double(n), h: u.h) }
    }

    // sorted orders frames left to right, then top to bottom, to compare layouts whatever the order.
    static func sorted(_ frames: [Frame]) -> [Frame] {
        frames.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    }

    // near reports whether two layouts hold the same frames within 1 point, whatever the order.
    static func near(_ a: [Frame], _ b: [Frame]) -> Bool {
        let a = sorted(a), b = sorted(b)
        return a.count == b.count && zip(a, b).allSatisfy { Actions.near($0, $1, tolerance: 1) }
    }

    // moves counts the moves made.
    var moves: Int {
        windows.calls.filter { if case .move = $0 { true } else { false } }.count
    }
}

// Choosing columns lays the free windows out in equal columns across the area and says so.
@Test @MainActor func testTilerColumns() {
    let rig = TileRig()
    let ids = [rig.add(), rig.add(), rig.add()]
    #expect(rig.tiler.run("tiling-columns"))
    rig.pass()
    #expect(TileRig.near(rig.frames(ids), rig.columns(3)))
    #expect(rig.changes == 1)
    #expect(rig.notifier.notes.map(\.title) == ["Tiling"])
}

// A window that opens joins the layout and one that closes leaves it, each after one pass.
@Test @MainActor func testTilerOpenAndClose() {
    let rig = TileRig()
    let a = rig.add(), b = rig.add()
    #expect(rig.tiler.run("tiling-columns"))
    rig.pass()
    let c = rig.add()
    rig.pass()
    #expect(TileRig.near(rig.frames([a, b, c]), rig.columns(3)))
    rig.windows.close(b)
    rig.pass()
    #expect(TileRig.near(rig.frames([a, c]), rig.columns(2)))
    #expect(rig.tiler.order.count == 2)
}

// A second pass with nothing changed moves nothing.
@Test @MainActor func testTilerSettledPassMovesNothing() {
    let rig = TileRig()
    rig.add()
    rig.add()
    #expect(rig.tiler.run("tiling-columns"))
    rig.pass()
    let moved = rig.moves
    rig.pass()
    #expect(rig.moves == moved)
}

// A window moved by hand after a mouse up floats, and the rest close up around it; choosing a mode
// again brings it back.
@Test @MainActor func testTilerDraggedWindowFloats() {
    let rig = TileRig()
    let a = rig.add(), b = rig.add(), c = rig.add()
    #expect(rig.tiler.run("tiling-columns"))
    rig.pass()
    rig.clock.advance(by: 1)
    let dropped = Frame(x: 900, y: 600, w: 700, h: 500)
    rig.windows.nudge(b, to: dropped)
    rig.tiler.mouseUp()
    rig.pass()
    #expect(rig.tiler.floated == [b])
    rig.pass()
    #expect(rig.windows.frame(b) == dropped)
    #expect(TileRig.near(rig.frames([a, c]), rig.columns(2)))
    #expect(rig.tiler.run("tiling-columns"))
    rig.pass()
    #expect(rig.tiler.floated.isEmpty)
    #expect(TileRig.near(rig.frames([a, b, c]), rig.columns(3)))
}

// Negative control: with tiling off a new window stays where it opened.
@Test @MainActor func testTilerOffMovesNothing() {
    let rig = TileRig()
    rig.add()
    let b = rig.add()
    let opened = rig.windows.frame(b)
    rig.pass()
    #expect(rig.moves == 0)
    #expect(rig.windows.frame(b) == opened)
}

// A pass while the mouse button is down, or while paused, moves nothing, including the pass the
// mode's save runs.
@Test @MainActor func testTilerHeldAndPausedMoveNothing() {
    let rig = TileRig()
    rig.add()
    rig.add()
    rig.pointer.primaryDown = true
    #expect(rig.tiler.run("tiling-columns"))
    rig.pass(mouseHeld: true)
    #expect(rig.moves == 0)
    rig.pointer.primaryDown = false
    rig.anchors.choices.paused = true
    rig.pass()
    #expect(rig.moves == 0)
}

// Anchored and stashed windows stay out of the layout.
@Test @MainActor func testTilerSkipsAnchoredAndStashed() {
    let rig = TileRig()
    let a = rig.add(), b = rig.add(), c = rig.add()
    rig.anchors.stashed.insert(c)
    let parked = rig.windows.frame(c)
    #expect(rig.tiler.run("tiling-columns"))
    rig.pass()
    #expect(TileRig.near(rig.frames([a, b]), rig.columns(2)))
    #expect(rig.windows.frame(c) == parked)
}

// Grow-main widens the main pane in tall and saves; at the largest share it does nothing.
@Test @MainActor func testTilerGrowMain() {
    let rig = TileRig()
    let was = rig.anchors.choices.tiling.ratio
    #expect(rig.tiler.run("grow-main"))
    #expect(rig.anchors.choices.tiling.ratio > was)
    #expect(rig.changes == 1)
    var grew = 0
    for _ in 0..<20 where rig.tiler.run("grow-main") {
        grew += 1
    }
    #expect(grew < 20)
    let top = rig.changes
    #expect(!rig.tiler.run("grow-main"))
    #expect(rig.changes == top)
}

// Cycling steps from off to the next mode.
@Test @MainActor func testTilerCycle() {
    let rig = TileRig()
    #expect(rig.tiler.run("cycle-tiling"))
    #expect(rig.anchors.choices.tiling.mode == Tiling.next(.off))
}

// Swap right trades the focused tiled window's place with its right neighbor and asks for a pass.
@Test @MainActor func testTilerSwapInLayout() {
    let rig = TileRig()
    let a = rig.add(), b = rig.add()
    #expect(rig.tiler.run("tiling-columns"))
    rig.pass()
    let left = rig.windows.frame(a)!.x < rig.windows.frame(b)!.x ? a : b
    let right = left == a ? b : a
    rig.windows.focusedID = left
    let before = rig.moors
    #expect(rig.tiler.run("swap-right"))
    #expect(rig.moors == before + 1)
    rig.pass()
    #expect(rig.windows.frame(left) == rig.columns(2)[1])
    #expect(rig.windows.frame(right) == rig.columns(2)[0])
}

// With tiling off, swap trades the two windows' frames.
@Test @MainActor func testTilerSwapFramesWhenOff() {
    let rig = TileRig()
    let a = rig.windows.add(bundle: "com.example.pad", frame: Frame(x: 100, y: 100, w: 600, h: 400))
    let b = rig.windows.add(bundle: "com.example.pad", frame: Frame(x: 1500, y: 100, w: 800, h: 500), focus: true)
    rig.windows.focusedID = a
    #expect(rig.tiler.run("swap-right"))
    #expect(rig.windows.frame(a) == Frame(x: 1500, y: 100, w: 800, h: 500))
    #expect(rig.windows.frame(b) == Frame(x: 100, y: 100, w: 600, h: 400))
}

// Focus left raises the neighbor on the left; with none it reports nothing done.
@Test @MainActor func testTilerFocus() {
    let rig = TileRig()
    let a = rig.windows.add(bundle: "com.example.pad", frame: Frame(x: 100, y: 100, w: 600, h: 400))
    let b = rig.windows.add(bundle: "com.example.pad", frame: Frame(x: 1500, y: 100, w: 800, h: 500), focus: true)
    #expect(rig.tiler.run("focus-left"))
    #expect(rig.windows.calls.last == .raise(a))
    rig.windows.focusedID = a
    #expect(!rig.tiler.run("focus-left"))
    _ = b
}
