import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// OrganizerRig is an organizer on fakes over one 3440x1440 ultrawide with three free windows in the
// channel, 5 points apart so they stack, the last one focused.
final class OrganizerRig {
    // windows is the fake window store.
    let windows = FakeWindows()
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // notifier records the banners.
    let notifier = FakeNotifier()
    // engine builds the organizer and runs the passes it asks for.
    let engine: Engine
    // anchors holds the choices.
    let anchors: Anchors
    // organizer is the organizer under test.
    let organizer: Organizer
    // pads lists the free windows, back to front.
    var pads: [WindowID] = []
    // moors counts the passes run.
    var moors = 0

    // init builds the rig with choices changed by edit and count free windows.
    init(count: Int = 3, _ edit: (inout Choices) -> Void = { _ in }) {
        var c = Choices()
        edit(&c)
        let clock = FakeClock()
        engine = newTestEngine(
            newTestPlatform(windows: windows, screens: screens, clock: clock, notifier: notifier, store: FakeStore(c)))
        anchors = engine.anchors
        organizer = engine.organizer
        for k in 0..<count {
            let d = Double(k)
            pads.append(
                windows.add(
                    bundle: "com.example.pad", frame: Frame(x: 900 + 5 * d, y: 200 + 5 * d, w: 700, h: 500),
                    focus: k == count - 1))
        }
        let rig = self
        engine.observers.passed = { _, _ in rig.moors += 1 }
    }

    // woke reports whether the organizer marked windows as changing, which sets the next pass.
    var woke: Bool { engine.passes.due != nil }

    // channel is the frame organize actions work in on the ultrawide.
    var channel: Frame {
        organizer.area(screens.current(), 0)
    }

    // frame returns the window's frame now.
    func frame(_ id: WindowID) -> Frame {
        windows.frame(id) ?? Frame(x: 0, y: 0, w: 0, h: 0)
    }

    // moved lists the windows the store was asked to move, in order.
    var moved: [WindowID] {
        windows.calls.compactMap {
            if case let .move(id, _, _) = $0 { return id }
            return nil
        }
    }
}

// Test 0: Tile columns gives three equal-width columns across the channel, left to right in the
// windows' order by x, flush with both channel edges.
@Test func testOrganizerTileColumns() {
    let rig = OrganizerRig()
    #expect(rig.organizer.run("tile-columns"))
    let c = rig.channel
    let f = rig.pads.map(rig.frame)
    #expect(c.w > 1000, "channel \(c)")
    #expect(f.map(\.w).allSatisfy { abs($0 - f[0].w) <= 1 }, "\(f)")
    #expect(abs(f[0].x - c.x) <= 1 && abs(f[2].x + f[2].w - (c.x + c.w)) <= 1, "\(f) in \(c)")
    #expect(f[0].x < f[1].x && f[1].x < f[2].x)
    #expect(f.allSatisfy { abs($0.y - c.y) <= 1 && abs($0.h - c.h) <= 1 })
    #expect(rig.woke)
}

// Test 1: Tile rows stacks the three windows top to bottom across the channel's full width.
@Test func testOrganizerTileRows() {
    let rig = OrganizerRig()
    #expect(rig.organizer.run("tile-rows"))
    let c = rig.channel
    let f = rig.pads.map(rig.frame)
    #expect(f.allSatisfy { abs($0.x - c.x) <= 1 && abs($0.w - c.w) <= 1 }, "\(f) in \(c)")
    #expect(f[0].y < f[1].y && f[1].y < f[2].y)
    #expect(abs(f[2].y + f[2].h - (c.y + c.h)) <= 1)
}

// Test 2: Cascade all steps each window down and right by the core's cascade step, the front window
// last and furthest so it stays on top.
@Test func testOrganizerCascade() {
    let rig = OrganizerRig()
    #expect(rig.organizer.run("cascade-all"))
    let f = rig.pads.map(rig.frame)
    #expect(abs(f[1].x - f[0].x - Tile.cascadeStep) <= 1 && abs(f[2].x - f[1].x - Tile.cascadeStep) <= 1, "\(f)")
    #expect(abs(f[1].y - f[0].y - Tile.cascadeStep) <= 1 && abs(f[2].y - f[1].y - Tile.cascadeStep) <= 1, "\(f)")
    #expect(rig.moved == rig.pads, "back-most first")
}

// Test 3: Cascade active app moves only the focused window's app.
@Test func testOrganizerCascadeActiveApp() {
    let rig = OrganizerRig()
    let other = rig.windows.add(bundle: "com.example.other", frame: Frame(x: 1200, y: 600, w: 600, h: 400))
    rig.windows.focusedID = rig.pads[2]
    #expect(rig.organizer.run("cascade-active-app"))
    #expect(rig.frame(other) == Frame(x: 1200, y: 600, w: 600, h: 400))
    #expect(Set(rig.moved) == Set(rig.pads))
}

// Test 4: Reverse all mirrors each window across the channel's middle.
@Test func testOrganizerReverse() {
    let rig = OrganizerRig()
    let before = rig.pads.map(rig.frame)
    #expect(rig.organizer.run("reverse-all"))
    let c = rig.channel
    for (b, a) in zip(before, rig.pads.map(rig.frame)) {
        #expect(abs((b.x - c.x) - (c.x + c.w - a.x - a.w)) <= 1 && a.w == b.w && a.y == b.y, "\(b) to \(a)")
    }
}

// Test 5: Cycle stacked windows raises the next window of the focused window's stack, and backward
// the one before, without moving anything.
@Test func testOrganizerCycleStacked() {
    let rig = OrganizerRig()
    #expect(rig.organizer.run("cycle-stacked-windows"))
    #expect(rig.windows.calls.last == .raise(rig.pads[0]))
    rig.windows.focusedID = rig.pads[2]
    #expect(rig.organizer.run("cycle-stacked-windows-backward"))
    #expect(rig.windows.calls.last == .raise(rig.pads[1]))
    #expect(rig.moved.isEmpty)
}

// Test 6: A window alone in its stack has nothing to cycle to.
@Test func testOrganizerCycleAlone() {
    let rig = OrganizerRig(count: 1)
    #expect(!rig.organizer.run("cycle-stacked-windows"))
    #expect(!rig.windows.calls.contains { if case .raise = $0 { true } else { false } })
}

// Test 7: A pinned window is never tiled.
@Test func testOrganizerSkipsPinned() {
    let rig = OrganizerRig { $0.slots = [.leftTop: "com.tinyspeck.slackmacgap"] }
    let slack = rig.windows.add(bundle: "com.tinyspeck.slackmacgap", frame: Frame(x: 1500, y: 200, w: 800, h: 600))
    rig.windows.focusedID = rig.pads[2]
    let s = rig.screens.current()
    let scan = rig.windows.scan(s, full: true)
    for m in rig.anchors.moor(Scene(screen: s.wide, windows: scan.windows, focused: scan.focused?.id, now: 1)) {
        rig.windows.move(m.id, to: m.frame, from: nil, behavior: Behaviors())
    }
    let held = rig.frame(slack)
    #expect(rig.anchors.pinned(rig.windows.scan(s, full: true).windows.first { $0.id == slack }!))
    #expect(rig.organizer.run("tile-columns"))
    #expect(rig.frame(slack) == held)
    #expect(Set(rig.moved.suffix(3)) == Set(rig.pads))
}

// Test 8: Nothing runs while paused.
@Test func testOrganizerPaused() {
    let rig = OrganizerRig { $0.paused = true }
    #expect(!rig.organizer.run("tile-columns"))
    rig.organizer.tidy(2)
    rig.organizer.undo()
    #expect(rig.moved.isEmpty && rig.moors == 0 && rig.notifier.notes.isEmpty)
}

// Test 9: Tidy two lines up the front two windows in two columns across the channel and runs a pass,
// leaving the third where it was.
@Test func testOrganizerTidy() {
    let rig = OrganizerRig()
    let back = rig.frame(rig.pads[0])
    rig.organizer.tidy(2)
    let c = rig.channel
    let a = rig.frame(rig.pads[1]), b = rig.frame(rig.pads[2])
    #expect(abs(a.x - c.x) <= 1 && abs(b.x + b.w - (c.x + c.w)) <= 1 && abs(a.w - b.w) <= 1, "\(a) \(b) in \(c)")
    #expect(rig.frame(rig.pads[0]) == back)
    #expect(rig.moors == 1)
}

// Test 10: Undo puts every tiled window back where it was before the tile, and says so.
@Test func testOrganizerUndo() {
    let rig = OrganizerRig()
    let before = rig.pads.map(rig.frame)
    #expect(rig.organizer.run("tile-columns"))
    #expect(rig.pads.map(rig.frame) != before)
    rig.organizer.undo()
    #expect(rig.pads.map(rig.frame) == before)
    #expect(rig.notifier.notes.map(\.title) == ["Tidy undone"])
}

// Test 11: An action the organizer does not own does nothing.
@Test func testOrganizerUnknown() {
    let rig = OrganizerRig()
    #expect(!rig.organizer.run("left-half"))
    #expect(rig.moved.isEmpty)
}

// Test 12: With no focused window nothing is organized.
@Test func testOrganizerNoFocus() {
    let rig = OrganizerRig()
    rig.windows.focusedID = nil
    #expect(!rig.organizer.run("tile-columns"))
    #expect(rig.moved.isEmpty)
}

// Test 13: With the first window filling the channel, cycle channel windows fills the channel with
// the next window by id and focuses it, wraps, and steps back; a window that already fills is raised
// without a move.
@Test func testOrganizerCycleChannel() {
    let rig = OrganizerRig()
    let s = rig.screens.current()
    let first = rig.windows.scan(s, full: true).windows.first { $0.id == rig.pads[0] }!
    #expect(!rig.engine.actions.fills(first, screens: s))
    #expect(rig.engine.actions.fill(first, screens: s))
    let fill = rig.frame(rig.pads[0])
    rig.windows.focusedID = rig.pads[0]
    let filled = rig.windows.scan(s, full: true).windows.first { $0.id == rig.pads[0] }!
    #expect(rig.engine.actions.fills(filled, screens: s), "\(fill)")
    #expect(rig.organizer.run("cycle-channel-windows"))
    #expect(Actions.near(rig.frame(rig.pads[1]), fill, tolerance: 1) && rig.windows.focusedID == rig.pads[1])
    #expect(rig.organizer.run("cycle-channel-windows"))
    #expect(Actions.near(rig.frame(rig.pads[2]), fill, tolerance: 1) && rig.windows.focusedID == rig.pads[2])
    let before = rig.moved.count
    #expect(rig.organizer.run("cycle-channel-windows"))
    #expect(rig.windows.focusedID == rig.pads[0] && rig.moved.count == before, "the fill is raised, not moved")
    #expect(rig.organizer.run("cycle-channel-windows-backward"))
    #expect(rig.windows.focusedID == rig.pads[2] && rig.moved.count == before)
}

// Test 14: A channel of one window has nothing to cycle to and moves nothing.
@Test func testOrganizerCycleChannelAlone() {
    let rig = OrganizerRig(count: 1)
    #expect(!rig.organizer.run("cycle-channel-windows"))
    #expect(rig.moved.isEmpty)
    #expect(!rig.windows.calls.contains { if case .raise = $0 { true } else { false } })
}

// Test 15: A pinned window in front is not on the channel's stage, so nothing cycles.
@Test func testOrganizerCycleChannelPinned() {
    let rig = OrganizerRig { $0.slots = [.leftTop: "com.tinyspeck.slackmacgap"] }
    let slack = rig.windows.add(bundle: "com.tinyspeck.slackmacgap", frame: Frame(x: 1500, y: 200, w: 800, h: 600))
    let s = rig.screens.current()
    let scan = rig.windows.scan(s, full: true)
    for m in rig.anchors.moor(Scene(screen: s.wide, windows: scan.windows, focused: scan.focused?.id, now: 1)) {
        rig.windows.move(m.id, to: m.frame, from: nil, behavior: Behaviors())
    }
    rig.windows.focusedID = slack
    let moves = rig.moved.count
    #expect(!rig.organizer.run("cycle-channel-windows"))
    #expect(rig.moved.count == moves)
}

// Test 16: A stashed window is skipped on the channel's stage.
@Test func testOrganizerCycleChannelSkipsStashed() {
    let rig = OrganizerRig()
    rig.anchors.stashed.insert(rig.pads[1])
    rig.windows.focusedID = rig.pads[0]
    #expect(rig.organizer.run("cycle-channel-windows"))
    #expect(rig.windows.focusedID == rig.pads[2])
    #expect(!rig.moved.contains(rig.pads[1]))
}
