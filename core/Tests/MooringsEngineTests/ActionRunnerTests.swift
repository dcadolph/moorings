import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// ActionRig is an action runner on fakes over one 3440x1440 ultrawide, with Slack anchored left top.
final class ActionRig {
    // windows is the fake window store.
    let windows = FakeWindows()
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // clock is the fake clock.
    let clock = FakeClock()
    // anchors holds the choices and the pins.
    let anchors: Anchors
    // runner is the action runner under test.
    let runner: ActionRunner
    // free is a free window in the channel, focused.
    let free: WindowID
    // slack is Slack's window, held in the left top slot after the first pass.
    let slack: WindowID

    // init builds the rig with choices changed by edit, then runs one pass so Slack is pinned.
    init(_ edit: (inout Choices) -> Void = { _ in }) {
        var c = Choices(slots: [.leftTop: "com.tinyspeck.slackmacgap"])
        edit(&c)
        anchors = Anchors(choices: c)
        let platform = newTestPlatform(windows: windows, screens: screens, clock: clock)
        runner = ActionRunner(platform: platform, anchors: anchors)
        slack = windows.add(bundle: "com.tinyspeck.slackmacgap", frame: Frame(x: 1500, y: 200, w: 800, h: 600))
        free = windows.add(bundle: "com.example.pad", frame: Frame(x: 1400, y: 300, w: 900, h: 700), focus: true)
        let rig = self
        runner.moor = { rig.pass() }
        pass()
    }

    // pass runs one Anchors pass on the fake windows and applies its moves.
    func pass() {
        clock.advance(by: 1)
        let s = screens.current()
        let scan = windows.scan(s, full: true)
        let moves = anchors.moor(
            Scene(screen: s.wide, windows: scan.windows, focused: scan.focused?.id, now: clock.now))
        for m in moves where !m.exitFullScreen {
            windows.move(m.id, to: m.frame, from: nil, behavior: Behaviors())
        }
    }

    // focus makes the window with id the focused one.
    func focus(_ id: WindowID) {
        windows.focusedID = id
    }

    // frame returns the window's frame now.
    func frame(_ id: WindowID) -> Frame {
        windows.frame(id) ?? Frame(x: 0, y: 0, w: 0, h: 0)
    }
}

// A half pressed again steps its cycle to the next size.
@Test func testRunnerHalfCycles() {
    let rig = ActionRig()
    #expect(rig.runner.run("left-half"))
    let first = rig.frame(rig.free)
    let ch = rig.anchors.channel(rig.screens.screens.usable[0])
    #expect(near(first, Frame(x: ch.x, y: ch.y, w: ch.w / 2, h: ch.h)))
    #expect(rig.runner.run("left-half"))
    let second = rig.frame(rig.free)
    #expect(second != first)
    #expect(second.x == ch.x)
}

// Maximize on a pin lifts it, and again lowers it.
@Test func testRunnerMaximizeLiftsPin() {
    let rig = ActionRig()
    #expect(
        rig.anchors.pinned(
            WindowInfo(
                id: rig.slack, bundle: "com.tinyspeck.slackmacgap", frame: rig.frame(rig.slack),
                onUltrawide: true, isMain: true)))
    rig.focus(rig.slack)
    #expect(rig.runner.run("maximize"))
    #expect(rig.anchors.isLifted(rig.slack))
    #expect(rig.runner.run("maximize"))
    #expect(!rig.anchors.isLifted(rig.slack))
}

// Restore after maximize puts the window back.
@Test func testRunnerRestoreAfterMaximize() {
    let rig = ActionRig()
    let start = rig.frame(rig.free)
    #expect(rig.runner.run("maximize"))
    #expect(rig.frame(rig.free) != start)
    #expect(rig.runner.run("restore"))
    #expect(near(rig.frame(rig.free), start))
}

// A fill stops at the next window.
@Test func testRunnerFillStopsAtWindow() {
    let rig = ActionRig()
    let wall = rig.windows.add(bundle: "com.example.wall", frame: Frame(x: 2800, y: 100, w: 400, h: 1000))
    rig.focus(rig.free)
    #expect(rig.runner.run("fill-right"))
    let f = rig.frame(rig.free)
    #expect(f.x == 1400)
    #expect(near(Frame(x: f.x + f.w, y: 0, w: 0, h: 0), Frame(x: rig.frame(wall).x, y: 0, w: 0, h: 0)))
}

// A looping chain steps one action per press and wraps.
@Test func testRunnerChainStepsAndLoops() {
    let rig = ActionRig { $0.chains = [Chain(name: "sides", steps: ["left-half", "right-half"], loops: true)] }
    let ch = rig.anchors.channel(rig.screens.screens.usable[0])
    #expect(rig.runner.run("chain:sides"))
    #expect(rig.frame(rig.free).x == ch.x)
    #expect(rig.runner.run("chain:sides"))
    #expect(
        near(
            Frame(x: rig.frame(rig.free).x + rig.frame(rig.free).w, y: 0, w: 0, h: 0),
            Frame(x: ch.x + ch.w, y: 0, w: 0, h: 0)))
    #expect(rig.runner.run("chain:sides"))
    #expect(rig.frame(rig.free).x == ch.x)
}

// Move cursor warps the pointer to the center of the window an action moved.
@Test func testRunnerMoveCursorWarps() {
    let pointer = FakePointer()
    let windows = FakeWindows()
    let screens = FakeScreens.ultrawide()
    let clock = FakeClock()
    var c = Choices()
    c.behavior.moveCursor = true
    let anchors = Anchors(choices: c)
    let platform = newTestPlatform(windows: windows, screens: screens, clock: clock, pointer: pointer)
    let runner = ActionRunner(platform: platform, anchors: anchors)
    let id = windows.add(bundle: "com.example.pad", frame: Frame(x: 1400, y: 300, w: 900, h: 700), focus: true)
    #expect(runner.run("left-half"))
    let f = windows.frame(id)!
    #expect(pointer.warps == [Point(x: f.x + f.w / 2, y: f.y + f.h / 2)])
}

// Nothing runs while paused.
@Test func testRunnerPausedRefuses() {
    let rig = ActionRig { $0.paused = true }
    let before = rig.windows.calls.count
    #expect(!rig.runner.run("left-half"))
    #expect(!rig.windows.calls.dropFirst(before).contains { if case .move = $0 { true } else { false } })
}

// A pin refuses an action that is not a part of its slot, such as center.
@Test func testRunnerPinRefusesCenter() {
    let rig = ActionRig()
    rig.focus(rig.slack)
    let held = rig.frame(rig.slack)
    #expect(!rig.runner.run("center"))
    #expect(rig.frame(rig.slack) == held)
}

// With slotStacks on, a half on a pin places it inside its slot.
@Test func testRunnerSlotStacksPlacesPart() {
    let rig = ActionRig { $0.slotStacks = true }
    rig.focus(rig.slack)
    let slot = rig.frame(rig.slack)
    #expect(rig.runner.run("left-half"))
    let f = rig.frame(rig.slack)
    #expect(near(f, Frame(x: slot.x, y: slot.y, w: slot.w / 2, h: slot.h)))
}

// Undo steps a window back to before its last move and redo steps forward again.
@Test func testRunnerUndoRedo() {
    let rig = ActionRig()
    let start = rig.frame(rig.free)
    #expect(rig.runner.run("left-half"))
    let moved = rig.frame(rig.free)
    #expect(rig.runner.run("undo-move"))
    #expect(near(rig.frame(rig.free), start))
    #expect(rig.runner.run("redo-move"))
    #expect(near(rig.frame(rig.free), moved))
}

// The routed actions go to the extra hook, and supports follows what the hook handles.
@Test func testRunnerRoutesExtra() {
    let rig = ActionRig()
    var ran: [String] = []
    #expect(!rig.runner.supports("stash"))
    #expect(rig.runner.supports("left-half"))
    rig.runner.extra = ExtraActions(
        handles: { $0 == "stash" },
        run: { name, _ in
            ran.append(name); return true
        })
    #expect(rig.runner.supports("stash"))
    #expect(rig.runner.run("stash"))
    #expect(ran == ["stash"])
}
