import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// StashRig is a stasher on fakes over one 3440x1440 ultrawide with one focused window.
@MainActor
final class StashRig {
    // windows is the fake window store.
    let windows = FakeWindows()
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // clock is the fake clock the rest check runs on.
    let clock = FakeClock()
    // pointer is the fake pointer, which tells the stasher of each move while it tracks.
    let pointer = FakePointer(Point(x: 1700, y: 700))
    // timers hands out the engine's schedulers, the stasher's second, after the workspaces'.
    let timers: FakeTimers
    // engine builds the stasher and runs the passes it wakes.
    let engine: Engine
    // anchors holds the choices.
    let anchors: Anchors
    // stasher is the stasher under test.
    let stasher: Stasher
    // id is the focused window.
    let id: WindowID
    // start is where the focused window begins, nearest the left edge.
    let start = Frame(x: 300, y: 300, w: 800, h: 600)

    // init builds the rig with choices and a window that refuses moves when refuses is set.
    init(_ choices: Choices = Choices(), refuses: Bool = false) {
        timers = FakeTimers(clock: clock)
        engine = newTestEngine(
            newTestPlatform(
                windows: windows, screens: screens, clock: clock, store: FakeStore(choices), pointer: pointer,
                timers: timers))
        anchors = engine.anchors
        id = windows.add(bundle: "com.example.pad", frame: start, refuses: refuses, focus: true)
        stasher = engine.stasher
    }

    // restTicks runs the stasher's rest check.
    var restTicks: FakeScheduler { timers.made[1] }

    // woke reports whether the stasher marked windows as changing, which sets the next pass.
    var woke: Bool { engine.passes.due != nil }

    // hidden is where start parks at the left edge.
    var hidden: Frame { Frame(x: Stash.sliver - start.w, y: start.y, w: start.w, h: start.h) }
    // shown is where start slides out to at the left edge.
    var shown: Frame { Frame(x: 0, y: start.y, w: start.w, h: start.h) }

    // held reports whether the fake mouse button is down.
    var held: Bool {
        get { pointer.buttonDown }
        set { pointer.buttonDown = newValue }
    }

    // watched records whether each track call started or stopped the pointer watch.
    var watched: [Bool] { pointer.tracks }

    // point moves the fake pointer to p as a person would, which tells the stasher while it tracks.
    func point(_ p: Point) {
        pointer.move(to: p)
    }

    // rest parks the window, takes the pointer off the sliver once, then rests it on the sliver past
    // the rest time.
    func rest() {
        stasher.run("stash")
        point(Point(x: 500, y: 500))
        point(Point(x: Stash.sliver / 2, y: 500))
        clock.advance(by: Stash.restSeconds + 0.05)
    }

    // moves counts the moves the stasher made on the window.
    var moves: Int {
        windows.calls.filter { if case .move = $0 { true } else { false } }.count
    }
}

// The stash action parks the focused window at the nearest edge with a sliver on screen.
@Test @MainActor func testStashParksWithSliver() {
    let rig = StashRig()
    #expect(rig.stasher.run("stash"))
    let f = rig.windows.frame(rig.id)
    #expect(f == rig.hidden)
    #expect(f.map { Stash.sliverRect($0, screen: rig.screens.screens.usable[0]).w } == Stash.sliver)
    #expect(rig.anchors.stashed == [rig.id])
    #expect(rig.stasher.entries.map(\.s.edge) == [.left])
    #expect(rig.watched == [true])
    #expect(rig.woke)
}

// A pointer that rests on the sliver slides the window out and raises it, on the rest scheduler.
@Test @MainActor func testStashRestSlidesOut() {
    let rig = StashRig()
    rig.rest()
    #expect(rig.windows.frame(rig.id) == rig.shown)
    #expect(rig.windows.calls.last == .raise(rig.id))
    #expect(rig.stasher.entries.first?.s.out == true)
    #expect(rig.restTicks.runs == 1)
}

// A pointer that leaves a slid-out window by more than the slack slides it back.
@Test @MainActor func testStashLeaveSlidesBack() {
    let rig = StashRig()
    rig.rest()
    rig.point(Point(x: rig.shown.x + rig.shown.w + Stash.slack + 20, y: 500))
    #expect(rig.windows.frame(rig.id) == rig.hidden)
    #expect(rig.stasher.entries.first?.s.out == false)
}

// Negative control: a pointer that rests off the sliver slides nothing.
@Test @MainActor func testStashHoverOffSliverSlidesNothing() {
    let rig = StashRig()
    rig.stasher.run("stash")
    let parked = rig.moves
    rig.point(Point(x: 500, y: 500))
    rig.point(Point(x: Stash.sliver + 40, y: 500))
    rig.clock.advance(by: 1)
    #expect(rig.windows.frame(rig.id) == rig.hidden)
    #expect(rig.moves == parked)
}

// A rest while a mouse button is held slides nothing.
@Test @MainActor func testStashButtonHeldSlidesNothing() {
    let rig = StashRig()
    rig.stasher.run("stash")
    rig.point(Point(x: 500, y: 500))
    rig.held = true
    rig.point(Point(x: Stash.sliver / 2, y: 500))
    rig.clock.advance(by: 1)
    #expect(rig.windows.frame(rig.id) == rig.hidden)
}

// The stash action again puts the window back where it began and stops the pointer watch.
@Test @MainActor func testStashToggleUnstashes() {
    let rig = StashRig()
    rig.stasher.run("stash")
    rig.windows.focusedID = rig.id
    #expect(rig.stasher.run("stash"))
    #expect(rig.windows.frame(rig.id) == rig.start)
    #expect(rig.anchors.stashed.isEmpty)
    #expect(rig.watched == [true, false])
}

// Unstash-all puts every window back and reports whether any was stashed.
@Test @MainActor func testStashUnstashAll() {
    let rig = StashRig()
    #expect(!rig.stasher.run("unstash-all"))
    rig.rest()
    #expect(rig.stasher.run("unstash-all"))
    #expect(rig.windows.frame(rig.id) == rig.start)
    #expect(rig.stasher.entries.isEmpty)
}

// A drag stash keeps the frame the drag began at as the one to come back to.
@Test @MainActor func testStashOriginalFromDrag() {
    let rig = StashRig()
    let began = Frame(x: 900, y: 200, w: 800, h: 600)
    let w = WindowInfo(id: rig.id, bundle: "com.example.pad", frame: rig.start, onUltrawide: true, isMain: true)
    #expect(rig.stasher.stash(w, edge: .left, original: began))
    rig.stasher.unstashAll()
    #expect(rig.windows.frame(rig.id) == began)
}

// A window that refuses the park move is not stashed and no watch starts.
@Test @MainActor func testStashRefusedIsUndone() {
    let rig = StashRig(refuses: true)
    #expect(!rig.stasher.run("stash"))
    #expect(rig.anchors.stashed.isEmpty)
    #expect(rig.stasher.entries.isEmpty)
    #expect(rig.watched.isEmpty)
}

// A paused moorings stashes nothing.
@Test @MainActor func testStashPausedDoesNothing() {
    var c = Choices()
    c.paused = true
    let rig = StashRig(c)
    #expect(!rig.stasher.run("stash"))
    #expect(rig.windows.frame(rig.id) == rig.start)
}

// On the ultrawide a side with an anchored app cannot take a stash, so the window parks at the
// bottom instead.
@Test @MainActor func testStashSkipsAnchoredSide() {
    let rig = StashRig(Choices(slots: [.leftTop: "com.example.chat"]))
    #expect(rig.stasher.run("stash"))
    #expect(rig.stasher.entries.map(\.s.edge) == [.bottom])
}

// A window the owner moved while parked is let go where it is, not slid.
@Test @MainActor func testStashOwnerMoveEndsStash() {
    let rig = StashRig()
    rig.stasher.run("stash")
    let moved = Frame(x: 600, y: 300, w: 800, h: 600)
    rig.windows.nudge(rig.id, to: moved)
    rig.point(Point(x: 500, y: 500))
    rig.point(Point(x: Stash.sliver / 2, y: 500))
    rig.clock.advance(by: 1)
    #expect(rig.windows.frame(rig.id) == moved)
    #expect(rig.stasher.entries.isEmpty)
    #expect(rig.watched == [true, false])
}

// A click inside a slid-out window ends its stash and leaves it out.
@Test @MainActor func testStashClickKeepsWindowOut() {
    let rig = StashRig()
    rig.rest()
    rig.stasher.clicked(Point(x: 400, y: 500))
    #expect(rig.stasher.entries.isEmpty)
    rig.point(Point(x: 2000, y: 500))
    #expect(rig.windows.frame(rig.id) == rig.shown)
}

// Pruning drops the stash of a window that is gone.
@Test @MainActor func testStashPrune() {
    let rig = StashRig()
    rig.stasher.run("stash")
    rig.stasher.prune(alive: [])
    #expect(rig.stasher.entries.isEmpty)
    #expect(rig.anchors.stashed.isEmpty)
}

// A drop with command held at a display's left, right or bottom edge stashes there; anywhere else,
// without command, or with command needed for snapping it does not.
@Test @MainActor func testStashDropEdge() {
    let rig = StashRig()
    #expect(rig.stasher.dropEdge(Point(x: 1, y: 700), held: .command) == .left)
    #expect(rig.stasher.dropEdge(Point(x: 3439, y: 700), held: .command) == .right)
    #expect(rig.stasher.dropEdge(Point(x: 1700, y: 1439), held: .command) == .bottom)
    #expect(rig.stasher.dropEdge(Point(x: 1700, y: 700), held: .command) == nil)
    #expect(rig.stasher.dropEdge(Point(x: 1, y: 700), held: []) == nil)
    var c = Choices()
    c.snapping.snapModifiers = ["command"]
    #expect(StashRig(c).stasher.dropEdge(Point(x: 1, y: 700), held: .command) == nil)
}
