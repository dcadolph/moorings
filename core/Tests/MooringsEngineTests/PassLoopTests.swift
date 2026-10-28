import MooringsCore
import MooringsEngine
import MooringsTesting
import Testing

// PassRig is a pass loop on fakes over one 3440x1440 ultrawide, with Slack anchored left top.
final class PassRig {
    // slackID is Slack's bundle.
    static let slackID = "com.tinyspeck.slackmacgap"
    // windows is the fake window store.
    let windows = FakeWindows()
    // screens is the fake ultrawide.
    let screens = FakeScreens.ultrawide()
    // clock is the fake clock.
    let clock = FakeClock(100)
    // scheduler runs the next pass as the clock advances.
    let scheduler: FakeScheduler
    // notifier records the banners.
    let notifier = FakeNotifier()
    // anchors decides where windows belong.
    let anchors: Anchors
    // key is the slot Slack is anchored in.
    let key: SlotKey
    // passes is the pass loop under test.
    let passes: PassLoop
    // moves records each move a pass applied and where it read back.
    var moves: [(Move, Frame?)] = []

    // init builds the rig with Slack anchored in the slot key.
    init(_ key: SlotKey = .leftTop) {
        self.key = key
        anchors = Anchors(choices: Choices(slots: [key: PassRig.slackID]))
        scheduler = FakeScheduler(clock: clock)
        let platform = Platform(windows: windows, screens: screens, overlay: FakeOverlay(), notifier: notifier, clock: clock,
                                scheduler: scheduler, store: FakeStore(), warpCursor: { _ in })
        passes = PassLoop(platform: platform, anchors: anchors)
        passes.moved = { [unowned self] m, _, got in moves.append((m, got)) }
    }

    // slot returns Slack's slot frame, which takes the whole side while the other slot is empty.
    var slot: Frame { strip(beside: anchors.channel(screens.screens.usable[0])) }

    // strip returns the strip beside channel ch on Slack's side.
    private func strip(beside ch: Frame) -> Frame {
        let u = screens.screens.usable[0]
        return key == .leftTop ? Frame(x: u.x, y: u.y, w: ch.x - u.x, h: u.h)
            : Frame(x: ch.x + ch.w, y: u.y, w: u.x + u.w - ch.x - ch.w, h: u.h)
    }

    // movesOf counts the moves the store got for the window with id.
    func movesOf(_ id: WindowID) -> Int {
        windows.calls.filter { if case let .move(m, _, _) = $0 { m == id } else { false } }.count
    }
}

// A pin out of place gets one move, and the pass reads it back where it was put.
@Test func testPassMovesPinOnce() {
    let rig = PassRig()
    let id = rig.windows.add(bundle: PassRig.slackID, frame: Frame(x: 1500, y: 200, w: 800, h: 600), focus: true)
    rig.passes.moor()
    #expect(rig.movesOf(id) == 1)
    #expect(near(rig.windows.frame(id), rig.slot))
    #expect(near(rig.moves.first?.1, rig.slot))
    rig.clock.advance(by: 1)
    rig.passes.moor()
    #expect(rig.movesOf(id) == 1)
}

// A window that refused a move is never moved again.
@Test func testPassRefusedNotRetried() {
    let rig = PassRig()
    let start = Frame(x: 1500, y: 200, w: 800, h: 600)
    let id = rig.windows.add(bundle: PassRig.slackID, frame: start, refuses: true, focus: true)
    rig.passes.moor()
    #expect(rig.movesOf(id) == 1)
    for _ in 0..<3 {
        rig.clock.advance(by: 1)
        rig.passes.moor()
    }
    #expect(rig.movesOf(id) == 1)
    #expect(rig.windows.frame(id) == start)
}

// A window that kept a larger size than it was given gets the one retry Anchors allows.
@Test func testPassRetriesLargerSize() {
    let rig = PassRig(.rightTop)
    let id = rig.windows.add(bundle: PassRig.slackID, frame: Frame(x: 1500, y: 200, w: 900, h: 600),
                             minW: rig.slot.w + 200, focus: true)
    rig.passes.moor()
    #expect(rig.movesOf(id) == 2)
    let f = rig.windows.frame(id)
    #expect(f.map { abs($0.x + $0.w - (rig.slot.x + rig.slot.w)) <= 1 } == true)
}

// A pin moved by hand is released, and the banner names the restore shortcut.
@Test func testPassReleasedNotifies() {
    let rig = PassRig()
    var released: [WindowID] = []
    rig.passes.released = { id, _ in released.append(id) }
    rig.passes.spell = { "<\($0.key)>" }
    let id = rig.windows.add(bundle: PassRig.slackID, frame: Frame(x: 1500, y: 200, w: 800, h: 600), focus: true)
    rig.passes.moor()
    rig.clock.advance(by: 3)
    rig.passes.moor()
    rig.windows.nudge(id, to: Frame(x: 900, y: 200, w: 700, h: 600))
    rig.passes.moor()
    #expect(released == [id])
    let key = Bindings(rig.anchors.choices).map["restore"].map { "<\($0.key)>" }
    #expect(rig.notifier.notes.map(\.title) == ["\(PassRig.slackID) released"])
    #expect(rig.notifier.notes.first?.body == PassLoop.releasedBody(key: key, greenButton: false))
}

// A refused window gets one banner a session when the platform tells of refusals.
@Test func testPassRefusedTellsOnce() {
    let rig = PassRig()
    rig.passes.tellsRefused = true
    _ = rig.windows.add(bundle: PassRig.slackID, frame: Frame(x: 1500, y: 200, w: 800, h: 600), refuses: true, focus: true)
    for _ in 0..<3 {
        rig.passes.moor()
        rig.clock.advance(by: 1)
    }
    #expect(rig.notifier.notes.map(\.title) == ["\(PassRig.slackID) runs as administrator"])
}

// Passes stop once reads find nothing new, before the settle time runs out, and an event starts
// them again within one poll.
@Test func testPassStillStopsAndWakeRestarts() {
    let rig = PassRig()
    _ = rig.windows.add(bundle: "com.example.pad", frame: Frame(x: 1500, y: 200, w: 800, h: 600), focus: true)
    rig.passes.wake()
    #expect(rig.scheduler.pendingAt == rig.clock.now + Pace.pollSeconds)
    rig.clock.advance(by: 0.8)
    #expect(rig.scheduler.pendingAt == nil)
    #expect(rig.scheduler.runs <= 3)
    let runs = rig.scheduler.runs
    rig.clock.advance(by: 30)
    #expect(rig.scheduler.runs == runs)
    rig.passes.wake()
    #expect(rig.scheduler.pendingAt == rig.clock.now + Pace.pollSeconds)
}

// The released banner names the green button where the platform has one.
@Test func testPassReleasedBody() {
    #expect(PassLoop.releasedBody(key: "K", greenButton: true) == "Click its green button to put it back,\nor press K.")
    #expect(PassLoop.releasedBody(key: nil, greenButton: true) == "Click its green button to put it back.")
    #expect(PassLoop.releasedBody(key: "K", greenButton: false) == "Press K on it to put it back.")
    #expect(PassLoop.releasedBody(key: nil, greenButton: false) == "Moorings leaves it where you put it.")
}
