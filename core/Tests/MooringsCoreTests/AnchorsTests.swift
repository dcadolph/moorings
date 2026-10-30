import Foundation
import Testing

@testable import MooringsCore

// wide is the usable frame of the 5120x1440 test ultrawide, below a 25 point menu bar.
let wide = Frame(x: 0, y: 25, w: 5120, h: 1415)

// leftFull is a lone left pin at the default widths.
let leftFull = Frame(x: 0, y: 25, w: 512, h: 1415)

// rightFull is a lone right pin at the default widths.
let rightFull = Frame(x: 2816, y: 25, w: 2304, h: 1415)

// slack and iterm are the bundles the scenarios anchor.
let slack = "com.tinyspeck.slackmacgap"
let iterm = "com.googlecode.iterm2"

// TestWorld holds windows that take the moves a pass returns, and counts the moves per window.
struct TestWorld {
    // Windows lists the movable windows, front-most first.
    var windows: [WindowInfo] = []
    // Moves counts the moves each window was given.
    var moves: [WindowID: Int] = [:]
    // Clock is the time in seconds the next pass sees.
    var clock = 1000.0
    // MouseHeld reports whether the primary button is down.
    var mouseHeld = false
    // Focused is the focused window, if any.
    var focused: WindowID?
    // Screen is the ultrawide's usable frame, nil when none is attached.
    var screen: Frame? = wide

    // add appends a window and returns its id.
    @discardableResult
    mutating func add(
        _ bundle: String, _ frame: Frame, main: Bool = true, panel: Bool = false,
        onUltrawide: Bool = true
    ) -> WindowID {
        let id = WindowID(windows.count + 1)
        windows.append(
            WindowInfo(
                id: id, bundle: bundle, frame: frame, onUltrawide: onUltrawide,
                isMain: main, isFilePanel: panel))
        return id
    }

    // frame returns the frame of the window with id.
    func frame(_ id: WindowID) -> Frame {
        windows.first { $0.id == id }!.frame
    }

    // set puts the window with id at frame, as the owner or the app would.
    mutating func set(_ id: WindowID, _ frame: Frame) {
        let i = windows.firstIndex { $0.id == id }!
        windows[i].frame = frame
    }

    // info returns the window with id.
    func info(_ id: WindowID) -> WindowInfo {
        windows.first { $0.id == id }!
    }

    // pass runs one moor pass and applies its moves.
    mutating func pass(_ anchors: Anchors) {
        let scene = Scene(screen: screen, windows: windows, focused: focused, mouseHeld: mouseHeld, now: clock)
        for move in anchors.moor(scene) {
            set(move.id, move.frame)
            moves[move.id, default: 0] += 1
        }
    }
}

// anchored returns Anchors with Slack alone on the left and iTerm alone on the right.
func anchored() -> Anchors {
    Anchors(choices: Choices(slots: [.leftTop: slack, .rightTop: iterm]))
}

// inChannel reports whether f lies inside the channel of anchors on the test ultrawide.
func inChannel(_ anchors: Anchors, _ f: Frame) -> Bool {
    let ch = anchors.channel(wide)
    return f.x >= ch.x && f.x + f.w <= ch.x + ch.w
}

// Test 0: Nothing anchored moves no window, the channel spans the screen, and the slots are empty.
@Test func testNothingAnchored() {
    let anchors = Anchors()
    var world = TestWorld()
    let a = world.add(slack, Frame(x: 2000, y: 100, w: 900, h: 700))
    let b = world.add(iterm, Frame(x: 100, y: 100, w: 900, h: 700))
    for _ in 0..<3 { world.pass(anchors) }
    #expect(world.moves[a] == nil && world.moves[b] == nil)
    #expect(anchors.channel(wide) == wide)
    #expect(anchors.pins().isEmpty)
}

// Test 1: Pins go to their strips, a free window is pushed into the channel and one too wide is
// shrunk to fit, as anchors_test.lua test 2.
@Test func testPushAndShrink() {
    let anchors = anchored()
    var world = TestWorld()
    let s = world.add(slack, Frame(x: 900, y: 100, w: 800, h: 600))
    let t = world.add(iterm, Frame(x: 100, y: 100, w: 800, h: 600))
    let small = world.add("com.apple.Safari", Frame(x: 0, y: 25, w: 800, h: 600))
    let big = world.add("com.google.Chrome", Frame(x: 300, y: 25, w: 4000, h: 1415))
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
    #expect(world.frame(t) == rightFull)
    #expect(world.frame(small) == Frame(x: 512, y: 25, w: 800, h: 600))
    #expect(world.frame(big) == Frame(x: 512, y: 25, w: 2304, h: 1415))
}

// Test 2: A free window already in the channel is never touched.
@Test func testChannelWindowUntouched() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let w = world.add("com.apple.Safari", Frame(x: 1000, y: 200, w: 800, h: 600))
    world.pass(anchors)
    world.pass(anchors)
    #expect(world.moves[w] == nil)
}

// Test 3: Without an ultrawide nothing moves.
@Test func testNoUltrawide() {
    let anchors = anchored()
    var world = TestWorld()
    world.screen = nil
    let w = world.add(slack, Frame(x: 900, y: 100, w: 800, h: 600))
    world.pass(anchors)
    #expect(world.moves[w] == nil)
}

// Test 4: Pins on another screen move to the ultrawide and free windows there stay put.
@Test func testOtherScreen() {
    let anchors = anchored()
    var world = TestWorld()
    let s = world.add(slack, Frame(x: 5300, y: 100, w: 800, h: 600), onUltrawide: false)
    let free = world.add("com.apple.Notes", Frame(x: 5300, y: 100, w: 800, h: 600), onUltrawide: false)
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
    #expect(world.moves[free] == nil)
}

// SlotCase is one slot frame expectation on the test ultrawide at the default widths.
struct SlotCase: Sendable, CustomTestStringConvertible {
    // Slots maps the chosen slots to bundles.
    let slots: [SlotKey: String]
    // Bundle is the pin whose frame is checked.
    let bundle: String
    // WantFrame is where the pin lands.
    let wantFrame: Frame

    // testDescription labels the case in test output.
    var testDescription: String { "\(bundle) in \(slots)" }
}

// slotCases mirrors anchors_test.lua tests 33 to 36 and 159 for the four slots.
let slotCases: [SlotCase] = [
    // Test 0: Lone top fills the side.
    SlotCase(slots: [.leftTop: "a"], bundle: "a", wantFrame: leftFull),
    // Test 1: Lone bottom fills the side.
    SlotCase(slots: [.leftBottom: "a"], bundle: "a", wantFrame: leftFull),
    // Test 2: Top half.
    SlotCase(slots: [.leftTop: "a", .leftBottom: "b"], bundle: "a", wantFrame: Frame(x: 0, y: 25, w: 512, h: 707)),
    // Test 3: Bottom half.
    SlotCase(slots: [.leftTop: "a", .leftBottom: "b"], bundle: "b", wantFrame: Frame(x: 0, y: 732, w: 512, h: 708)),
    // Test 4: Right bottom.
    SlotCase(
        slots: [.rightTop: "a", .rightBottom: "b"], bundle: "b", wantFrame: Frame(x: 2816, y: 732, w: 2304, h: 708)),
    // Test 5: Lone right bottom.
    SlotCase(slots: [.rightBottom: "a"], bundle: "a", wantFrame: rightFull),
]

// testSlotFrames checks where each pin lands, matching the Lua frames for the same widths.
@Test(arguments: slotCases)
func testSlotFrames(test: SlotCase) {
    let anchors = Anchors(choices: Choices(slots: test.slots))
    var world = TestWorld()
    let w = world.add(test.bundle, Frame(x: 1000, y: 200, w: 800, h: 600))
    world.add(test.bundle == "a" ? "b" : "a", Frame(x: 1500, y: 200, w: 800, h: 600))
    world.pass(anchors)
    #expect(world.frame(w) == test.wantFrame)
}

// Test 5: A pin holds the app's main window. With slotStacks on its other window stacks in the
// slot; with it off the other window is kept in the channel.
@Test func testPinHoldsMainWindow() {
    for stacks in [true, false] {
        let anchors = anchored()
        anchors.choices.slotStacks = stacks
        var world = TestWorld()
        let other = world.add(slack, Frame(x: 0, y: 200, w: 800, h: 600), main: false)
        let main = world.add(slack, Frame(x: 1500, y: 200, w: 800, h: 600))
        world.pass(anchors)
        world.set(main, leftFull)
        world.windows[0].isMain = true
        world.windows[1].isMain = false
        world.pass(anchors)
        #expect(world.frame(main) == leftFull, "stacks \(stacks)")
        #expect(world.frame(other) == (stacks ? leftFull : Frame(x: 512, y: 200, w: 800, h: 600)), "stacks \(stacks)")
        #expect(anchors.pinned(world.info(main)), "stacks \(stacks)")
        #expect(anchors.pinned(world.info(other)) == stacks, "stacks \(stacks)")
        #expect(anchors.slotWindows(.leftTop) == (stacks ? [other, main] : [main]), "stacks \(stacks)")
    }
}

// Test 6: An open or save panel is never pinned and is left where it is, unlike the app's other
// windows, the side keeps its strip, and the document after it takes the slot, as
// anchors_test.lua tests 22 and 197.
@Test func testFilePanelNeverPinned() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(iterm, rightFull)
    let picker = world.add(slack, Frame(x: 100, y: 100, w: 996, h: 1000), panel: true)
    anchors.launch(now: world.clock)
    world.pass(anchors)
    #expect(!anchors.pinned(world.info(picker)))
    #expect(world.moves[picker] == nil)
    #expect(anchors.channel(wide).x == leftFull.w)
    world.windows[1].isMain = false
    let doc = world.add(slack, Frame(x: 1200, y: 200, w: 800, h: 600))
    world.pass(anchors)
    #expect(world.frame(doc) == leftFull)
    #expect(!anchors.pinned(world.info(picker)))
    #expect(world.moves[picker] == nil)
}

// Test 7: Nothing moves while the mouse button is held, and the next pass after it is let go
// moves the window.
@Test func testMouseHeld() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    let w = world.add("com.apple.Safari", Frame(x: 0, y: 25, w: 800, h: 600))
    world.mouseHeld = true
    world.pass(anchors)
    #expect(world.moves[w] == nil)
    world.mouseHeld = false
    world.pass(anchors)
    #expect(world.frame(w) == Frame(x: 512, y: 25, w: 800, h: 600))
}

// Test 8: Weigh anchor holds nothing, and Drop anchor moors again.
@Test func testPaused() {
    let anchors = anchored()
    anchors.choices.paused = true
    var world = TestWorld()
    let s = world.add(slack, Frame(x: 900, y: 100, w: 800, h: 600))
    world.pass(anchors)
    #expect(world.moves[s] == nil)
    anchors.choices.paused = false
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
}

// Test 9: A window that keeps moving back is held off for a minute, as anchors_test.lua test 25.
@Test func testFightHold() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    let w = world.add("com.apple.Safari", Frame(x: 0, y: 25, w: 800, h: 600))
    world.pass(anchors)
    for _ in 0..<3 {
        world.set(w, Frame(x: 0, y: 25, w: 800, h: 600))
        world.clock += 1
        world.pass(anchors)
    }
    #expect(world.moves[w] == 4)
    world.set(w, Frame(x: 0, y: 25, w: 800, h: 600))
    world.clock += 1
    world.pass(anchors)
    #expect(world.moves[w] == 4 && world.frame(w).x == 0)
    world.clock += 61
    world.pass(anchors)
    #expect(world.frame(w).x == 512)
}

// Test 10: A window the channel narrowed grows back when the channel widens, and one the owner
// resized after the clamp keeps the owner's width, as anchors_test.lua tests 9 and 10.
@Test func testGrowBack() {
    for resized in [false, true] {
        let anchors = anchored()
        var world = TestWorld()
        world.add(slack, leftFull)
        world.add(iterm, rightFull)
        let w = world.add("com.google.Chrome", Frame(x: 600, y: 25, w: 2200, h: 1415))
        anchors.setWidths(Widths(left: 20, right: 40))
        world.pass(anchors)
        #expect(world.frame(w).w == 2048)
        if resized {
            var f = world.frame(w)
            f.w = 1200
            world.set(w, f)
        }
        anchors.setWidths(Widths(left: 10, right: 30))
        world.pass(anchors)
        #expect(world.frame(w).w == (resized ? 1200 : 2200))
    }
}

// Test 11: A side whose anchored app has no window joins the channel, and the app's window
// takes the strip back when it shows, as anchors_test.lua tests 56 and 184.
@Test func testEmptySideJoinsChannel() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.pass(anchors)
    let ch = anchors.channel(wide)
    #expect(ch.x == 512 && ch.x + ch.w == 5120)
    #expect(anchors.emptySides() == [.right])
    world.add(iterm, Frame(x: 1000, y: 200, w: 800, h: 600))
    world.pass(anchors)
    #expect(anchors.channel(wide).w == 2304)
}

// Test 12: An app moorings just opened keeps its strip for 30 seconds while its window is on the
// way, then gives it to the channel.
@Test func testOpeningKeepsSpace() {
    let anchors = Anchors()
    var world = TestWorld()
    world.pass(anchors)
    anchors.lock(.rightTop, iterm, now: world.clock)
    world.pass(anchors)
    #expect(anchors.channel(wide).w == 2816)
    world.clock += 31
    world.pass(anchors)
    #expect(anchors.channel(wide).w == 5120)
}

// Test 13: A launch keeps every anchored app's strip through the first pass and lists the apps
// with no window to open, as anchors_test.lua test 187.
@Test func testLaunchOpensMissing() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    anchors.launch(now: world.clock)
    world.pass(anchors)
    #expect(anchors.opening() == [iterm])
    #expect(anchors.channel(wide).x + anchors.channel(wide).w == 2816)
    world.clock += 31
    world.pass(anchors)
    #expect(anchors.channel(wide).x + anchors.channel(wide).w == 5120)
}

// Test 14: Assigning an app that sits in another slot moves it, emptying a slot frees its app,
// and Unanchor all empties every slot.
@Test func testAssign() {
    let anchors = anchored()
    anchors.assign(.leftBottom, iterm)
    #expect(anchors.assignments()[.rightTop] == "")
    #expect(anchors.assignments()[.leftBottom] == iterm)
    anchors.assign(.leftTop, "")
    #expect(anchors.pins() == [Pin(bundle: iterm, slot: .leftBottom)])
    anchors.clearSlots()
    #expect(anchors.pins().isEmpty)
    #expect(SlotKey.allCases.allSatisfy { anchors.assignments()[$0] == "" })
}

// Test 15: Choices survive an encode and decode, so a quit and reopen restores the layout, and
// junk or out of range values fall back to the defaults.
@Test func testChoicesRoundTrip() throws {
    var c = Choices(slots: [.leftTop: slack, .rightBottom: iterm])
    c.widths = Widths(left: 8, right: 46)
    c.heights = Heights(left: 33, right: 75)
    c.paused = true
    c.widthPresets = [Widths(left: 12, right: 38)]
    let data = try Choices.encode(c)
    #expect(Choices.decode(data).choices == c)
    #expect(c.restoringDefaults().widthPresets == [Widths(left: 12, right: 38)])
    let reopened = Anchors(choices: Choices.decode(data).choices)
    #expect(reopened.widths == Widths(left: 8, right: 46))
    #expect(reopened.heights == Heights(left: 33, right: 75))
    #expect(reopened.pins() == [Pin(bundle: slack, slot: .leftTop), Pin(bundle: iterm, slot: .rightBottom)])
    #expect(Choices.decode(Data("garbage".utf8)).choices == Choices())
    let bad = Data(
        #"{"slots":{"left-top":"a","middle":"b"},"widths":{"left":60,"right":45},"heights":{"left":5,"right":50}}"#.utf8
    )
    let fixed = Anchors(choices: Choices.decode(bad).choices)
    #expect(fixed.pins() == [Pin(bundle: "a", slot: .leftTop)])
    #expect(fixed.widths == Layout.defaultWidths)
    #expect(fixed.heights == Heights(left: 50, right: 50))
    #expect(fixed.choices.widthPresets.isEmpty)
}

// Test 16: A cast-off window stays over a strip and keeps a width wider than the channel through
// ten passes while another free window is still settled, and unchecking settles it on the next
// pass, as anchors_test.lua test 202.
@Test func testCastOffStaysPut() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let other = world.add("com.google.Chrome", Frame(x: 1000, y: 100, w: 800, h: 600))
    let w = world.add("com.apple.Safari", Frame(x: 1000, y: 100, w: 800, h: 600))
    world.pass(anchors)
    world.focused = w
    #expect(anchors.castReason(world.info(w), ultrawide: wide) == nil)
    #expect(anchors.toggleCastOff(world.info(w), ultrawide: wide))
    #expect(anchors.isCastOff(w))
    let over = Frame(x: 3000, y: 100, w: 3000, h: 900)
    world.set(w, over)
    world.set(other, over)
    for _ in 0..<10 { world.pass(anchors) }
    #expect(world.frame(w) == over)
    #expect(world.moves[w] == nil)
    #expect(inChannel(anchors, world.frame(other)))
    #expect(anchors.toggleCastOff(world.info(w), ultrawide: wide))
    #expect(!anchors.isCastOff(w))
    world.pass(anchors)
    #expect(inChannel(anchors, world.frame(w)))
}

// Swift only: a stashed window parked over a strip is never pulled back into the channel, and once
// unstashed it is held in the channel again.
@Test func testStashedStaysPut() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let w = world.add("com.apple.Safari", Frame(x: 1000, y: 100, w: 800, h: 600))
    world.pass(anchors)
    let parked = Frame(x: 5108, y: 100, w: 800, h: 600)
    anchors.stashed.insert(w)
    world.set(w, parked)
    for _ in 0..<10 { world.pass(anchors) }
    #expect(world.frame(w) == parked)
    #expect(world.moves[w] == nil)
    anchors.stashed.remove(w)
    world.pass(anchors)
    #expect(inChannel(anchors, world.frame(w)))
    anchors.stashed.insert(w)
    anchors.prune(alive: [])
    #expect(anchors.stashed.isEmpty)
}

// Test 17: Cast off drops the record of a window the channel narrowed, so after the cast off ends
// it no longer grows back to its own width and instead keeps filling the wider channel.
@Test func testCastOffDropsClamp() {
    for cast in [true, false] {
        let anchors = anchored()
        var world = TestWorld()
        world.add(slack, leftFull)
        world.add(iterm, rightFull)
        let w = world.add("com.apple.Safari", Frame(x: 512, y: 25, w: 3000, h: 1000))
        world.pass(anchors)
        #expect(world.frame(w).w == 2304)
        if cast {
            anchors.toggleCastOff(world.info(w), ultrawide: wide)
            world.pass(anchors)
            anchors.toggleCastOff(world.info(w), ultrawide: wide)
            world.pass(anchors)
        }
        anchors.setWidths(Widths(left: 10, right: 20))
        world.pass(anchors)
        #expect(world.frame(w).w == (cast ? anchors.channel(wide).w : 3000))
    }
}

// Test 18: A closed cast-off window is forgotten, so a new window with its id is held in the
// channel again, as anchors_test.lua test 204.
@Test func testCastOffClosed() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let w = world.add("com.apple.Safari", Frame(x: 1000, y: 100, w: 800, h: 600))
    world.pass(anchors)
    anchors.toggleCastOff(world.info(w), ultrawide: wide)
    #expect(anchors.isCastOff(w))
    anchors.prune(alive: [1, 2])
    world.set(w, Frame(x: 3000, y: 100, w: 800, h: 600))
    world.pass(anchors)
    #expect(!anchors.isCastOff(w))
    #expect(inChannel(anchors, world.frame(w)))
}

// CastReasonCase is one Cast off availability expectation.
struct CastReasonCase: Sendable, CustomTestStringConvertible {
    // Window is the focused window, nil when none.
    let window: WindowInfo?
    // WantReason is the tooltip that says why it cannot be cast off, nil when it can.
    let wantReason: String?

    // testDescription labels the case in test output.
    var testDescription: String { wantReason ?? "allowed" }
}

// castReasonCases mirrors anchors_test.lua test 205.
let castReasonCases: [CastReasonCase] = [
    // Test 0: No window.
    CastReasonCase(window: nil, wantReason: "There is no focused window to cast off."),
    // Test 1: Pinned.
    CastReasonCase(
        window: WindowInfo(id: 1, bundle: slack, frame: leftFull, onUltrawide: true, isMain: true),
        wantReason: "Pinned windows stay in their slot."),
    // Test 2: Other screen.
    CastReasonCase(
        window: WindowInfo(
            id: 3, bundle: "com.apple.Notes", frame: Frame(x: 5300, y: 100, w: 600, h: 400),
            onUltrawide: false, isMain: true),
        wantReason: "Only windows on the ultrawide are held in the channel."),
    // Test 3: Free.
    CastReasonCase(
        window: WindowInfo(
            id: 4, bundle: "com.apple.Safari", frame: Frame(x: 1000, y: 100, w: 800, h: 600),
            onUltrawide: true, isMain: true), wantReason: nil),
]

// testCastReason checks when Cast off is disabled and that a pin is refused and left in place.
@Test(arguments: castReasonCases)
func testCastReason(test: CastReasonCase) {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.pass(anchors)
    #expect(anchors.castReason(test.window, ultrawide: wide) == test.wantReason)
    #expect(anchors.toggleCastOff(test.window, ultrawide: wide) == (test.wantReason == nil))
    world.pass(anchors)
    #expect(world.frame(1) == leftFull && world.moves[1] == nil)
}

// Test 19: Cast off has no reason to give without an ultrawide.
@Test func testCastReasonNoUltrawide() {
    let w = WindowInfo(
        id: 4, bundle: "com.apple.Safari", frame: Frame(x: 1000, y: 100, w: 800, h: 600),
        onUltrawide: false, isMain: true)
    #expect(Anchors().castReason(w, ultrawide: nil) == "Only windows on the ultrawide are held in the channel.")
}

// Test 20: A cast-off window whose app is anchored becomes a pin and is no longer cast off, and
// cast off is not part of the saved choices, as anchors_test.lua test 206.
@Test func testCastOffBecomesPin() throws {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let w = world.add("com.apple.Safari", Frame(x: 1000, y: 100, w: 800, h: 600))
    world.pass(anchors)
    let before = try Choices.encode(anchors.choices)
    anchors.toggleCastOff(world.info(w), ultrawide: wide)
    #expect(try Choices.encode(anchors.choices) == before)
    anchors.assign(.leftBottom, "com.apple.Safari")
    world.pass(anchors)
    #expect(anchors.pinned(world.info(w)))
    #expect(!anchors.isCastOff(w))
}

// Swift only: an app's one on-screen window counts as main when the app names none of them main.
@Test func testPromotingLone() {
    let f = Frame(x: 0, y: 0, w: 100, h: 100)
    let windows = [
        WindowInfo(id: 1, bundle: iterm, frame: f, onUltrawide: true, isMain: false),
        WindowInfo(id: 2, bundle: slack, frame: f, onUltrawide: true, isMain: false),
        WindowInfo(id: 3, bundle: slack, frame: f, onUltrawide: true, isMain: false),
        WindowInfo(id: 4, bundle: "com.apple.TextEdit", frame: f, onUltrawide: true, isMain: false),
        WindowInfo(id: 5, bundle: "com.apple.TextEdit", frame: f, onUltrawide: true, isMain: true),
        WindowInfo(id: 6, bundle: "com.apple.Preview", frame: f, onUltrawide: true, isMain: false, isFilePanel: true),
    ]
    let got = WindowInfo.promotingLone(windows).map(\.isMain)
    #expect(got == [true, false, false, false, true, false])
}

// Swift only: a busy app's windows from the last scan are carried while still on screen, at their
// current frame with the green button moved alongside, and dropped once off screen.
@Test func testCarrying() {
    let last = [
        WindowInfo(
            id: 1, bundle: "com.apple.systempreferences", frame: Frame(x: 0, y: 30, w: 723, h: 1410),
            onUltrawide: true, isMain: true, zoomRect: Frame(x: 52, y: 36, w: 14, h: 14)),
        WindowInfo(
            id: 2, bundle: "com.apple.systempreferences", frame: Frame(x: 900, y: 200, w: 400, h: 300),
            onUltrawide: true, isMain: false),
    ]
    let got = WindowInfo.carrying(last, frames: [1: Frame(x: 100, y: 40, w: 723, h: 1400)])
    #expect(got.map(\.id) == [1])
    #expect(got.first?.frame == Frame(x: 100, y: 40, w: 723, h: 1400))
    #expect(got.first?.zoomRect == Frame(x: 152, y: 46, w: 14, h: 14))
    #expect(got.first?.isMain == true)
    #expect(WindowInfo.carrying([], frames: [1: Frame(x: 0, y: 0, w: 1, h: 1)]).isEmpty)
    #expect(WindowInfo.carrying(last, frames: [:]).isEmpty)
}
// Swift only: a pin holds an app whose only on-screen window is not its main window, by promoting
// it with slotStacks off and as a stacked window with it on.
@Test func testPinHoldsLoneWindow() {
    for stacks in [true, false] {
        let anchors = anchored()
        anchors.choices.slotStacks = stacks
        let w = WindowInfo(
            id: 9, bundle: iterm, frame: Frame(x: 1000, y: 200, w: 800, h: 600), onUltrawide: true, isMain: false)
        #expect(anchors.pinned(w) == stacks, "stacks \(stacks)")
        #expect(anchors.pinned(WindowInfo.promotingLone([w])[0]), "stacks \(stacks)")
    }
}

// testSplitSides checks that only a side with two anchored apps showing splits into rows.
@Test func testSplitSides() {
    let anchors = Anchors(
        choices: Choices(slots: [.leftTop: slack, .leftBottom: "com.apple.finder", .rightTop: iterm]))
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    world.pass(anchors)
    #expect(anchors.splitSides().isEmpty)
    world.add("com.apple.finder", Frame(x: 1000, y: 300, w: 900, h: 400))
    world.pass(anchors)
    #expect(anchors.splitSides() == [.left])
}

// testChannelEdgesFollow checks that when the channel moves, a window filling it keeps filling it,
// a window on one edge slides with that edge at its own width, and one off both edges stays.
@Test func testChannelEdgesFollow() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let fill = world.add("com.apple.TextEdit", Frame(x: 512, y: 25, w: 2304, h: 1415))
    let half = world.add("com.apple.Safari", Frame(x: 512, y: 100, w: 1000, h: 800))
    let rightSide = world.add("com.apple.Notes", Frame(x: 2016, y: 100, w: 800, h: 800))
    let mid = world.add("com.apple.Preview", Frame(x: 1200, y: 200, w: 600, h: 500))
    world.pass(anchors)
    #expect(world.moves.isEmpty)
    anchors.setWidths(Widths(left: 16, right: 40))
    world.pass(anchors)
    let ch = anchors.channel(wide)
    #expect(world.frame(fill) == Frame(x: ch.x, y: 25, w: ch.w, h: 1415))
    #expect(world.frame(half) == Frame(x: ch.x, y: 100, w: 1000, h: 800))
    #expect(world.frame(rightSide) == Frame(x: ch.x + ch.w - 800, y: 100, w: 800, h: 800))
    #expect(world.moves[mid] == nil)
    anchors.setWidths(Widths(left: 10, right: 45))
    world.pass(anchors)
    #expect(world.frame(fill) == Frame(x: 512, y: 25, w: 2304, h: 1415))
}

// testHangOffBottom checks that a free window the owner drags down in the channel stays where it
// was dropped with its top band on screen, is still held between the strips side to side and below
// the channel top, and keeps hanging on later passes.
@Test func testHangOffBottom() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let full = world.add("com.apple.Safari", Frame(x: 512, y: 25, w: 2304, h: 1415))
    let deep = world.add("com.apple.Notes", Frame(x: 1000, y: 200, w: 800, h: 600))
    let side = world.add("com.apple.TextEdit", Frame(x: 600, y: 100, w: 800, h: 1000))
    let high = world.add("com.apple.Preview", Frame(x: 1200, y: 200, w: 600, h: 500))
    world.pass(anchors)
    world.mouseHeld = true
    world.pass(anchors)
    world.set(full, Frame(x: 512, y: 400, w: 2304, h: 1415))
    world.set(deep, Frame(x: 1000, y: 1420, w: 800, h: 600))
    world.set(side, Frame(x: 100, y: 900, w: 800, h: 1000))
    world.set(high, Frame(x: 1200, y: 0, w: 600, h: 500))
    world.mouseHeld = false
    for _ in 1...3 {
        world.clock += 1
        world.pass(anchors)
    }
    #expect(world.frame(full) == Frame(x: 512, y: 400, w: 2304, h: 1415))
    #expect(world.moves[full] == nil)
    #expect(world.frame(deep) == Frame(x: 1000, y: 1400, w: 800, h: 600))
    #expect(world.frame(side) == Frame(x: 512, y: 900, w: 800, h: 1000))
    #expect(world.frame(high) == Frame(x: 1200, y: 25, w: 600, h: 500))
}

// testAppMoveStaysInside checks that a window its own app moves past the channel bottom is pulled
// back inside, and that a window the owner hung is pulled back once its app moves it.
@Test func testAppMoveStaysInside() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, leftFull)
    world.add(iterm, rightFull)
    let own = world.add("com.apple.Safari", Frame(x: 512, y: 25, w: 2304, h: 1415))
    let hung = world.add("com.apple.Notes", Frame(x: 1000, y: 200, w: 800, h: 600))
    world.pass(anchors)
    world.set(own, Frame(x: 512, y: 400, w: 2304, h: 1415))
    world.clock += 1
    world.pass(anchors)
    world.mouseHeld = true
    world.pass(anchors)
    world.set(hung, Frame(x: 1000, y: 1000, w: 800, h: 600))
    world.mouseHeld = false
    world.pass(anchors)
    #expect(world.frame(own) == Frame(x: 512, y: 25, w: 2304, h: 1415))
    #expect(world.frame(hung) == Frame(x: 1000, y: 1000, w: 800, h: 600))
    world.set(hung, Frame(x: 1000, y: 1100, w: 800, h: 600))
    world.clock += 1
    world.pass(anchors)
    #expect(world.frame(hung) == Frame(x: 1000, y: 840, w: 800, h: 600))
}

// Swift only: an anchored app's other window is left alone off the ultrawide and while cast off,
// and is kept in the channel otherwise.
@Test func testAnchoredAppOtherWindows() {
    let tests: [(name: String, onUltrawide: Bool, castOff: Bool, want: Frame)] = [
        ("in the channel", true, false, Frame(x: 512, y: 200, w: 800, h: 600)),
        ("off the ultrawide", false, false, Frame(x: 0, y: 200, w: 800, h: 600)),
        ("cast off", true, true, Frame(x: 0, y: 200, w: 800, h: 600)),
    ]
    for test in tests {
        let anchors = anchored()
        anchors.choices.slotStacks = false
        var world = TestWorld()
        world.add(slack, leftFull)
        let other = world.add(
            slack, Frame(x: 1000, y: 200, w: 800, h: 600), main: false,
            onUltrawide: test.onUltrawide)
        world.pass(anchors)
        if test.castOff {
            anchors.toggleCastOff(world.info(other), ultrawide: wide)
        }
        world.set(other, Frame(x: 0, y: 200, w: 800, h: 600))
        world.clock += 1
        world.pass(anchors)
        #expect(world.frame(other) == test.want, "\(test.name)")
    }
}

// testSlotStacksHoldsAll checks that with slotStacks on a slot holds all three of its app's windows
// on the ultrawide, each at the slot frame, and leaves the one on another display alone.
@Test func testSlotStacksHoldsAll() {
    let anchors = anchored()
    var world = TestWorld()
    let main = world.add(slack, Frame(x: 1500, y: 200, w: 800, h: 600))
    let second = world.add(slack, Frame(x: 2000, y: 300, w: 700, h: 500), main: false)
    let third = world.add(slack, Frame(x: 2500, y: 400, w: 600, h: 400), main: false)
    let away = world.add(slack, Frame(x: -1000, y: 200, w: 800, h: 600), main: false, onUltrawide: false)
    world.pass(anchors)
    for id in [main, second, third] {
        #expect(world.frame(id) == leftFull, "window \(id)")
    }
    #expect(world.frame(away) == Frame(x: -1000, y: 200, w: 800, h: 600))
    #expect(anchors.slotWindows(.leftTop) == [main, second, third])
    #expect(anchors.slotWindows(.rightTop).isEmpty)
}

// testSlotStacksBackOn checks that windows a slot let go into the channel when slotStacks went off,
// including one with a part and one moved by hand while free, stack in the slot again when it goes
// back on, rather than being read as released.
@Test func testSlotStacksBackOn() {
    let anchors = anchored()
    var world = TestWorld()
    let main = world.add(slack, Frame(x: 1500, y: 200, w: 800, h: 600))
    let second = world.add(slack, Frame(x: 2000, y: 300, w: 700, h: 500), main: false)
    let third = world.add(slack, Frame(x: 2500, y: 400, w: 600, h: 400), main: false)
    world.pass(anchors)
    #expect(anchors.holdPart(second, "left-half", Frame(x: 0, y: 25, w: 256, h: 1415)))
    world.clock += 1
    world.pass(anchors)
    anchors.choices.slotStacks = false
    world.clock += 1
    world.pass(anchors)
    #expect(world.frame(second) != leftFull)
    #expect(world.frame(third) != leftFull)
    world.set(third, Frame(x: 1800, y: 300, w: 600, h: 400))
    world.clock += 5
    world.pass(anchors)
    anchors.choices.slotStacks = true
    for _ in 0..<2 {
        world.clock += 5
        world.pass(anchors)
    }
    for id in [main, second, third] {
        #expect(world.frame(id) == leftFull, "window \(id)")
        #expect(!anchors.isReleased(id), "window \(id)")
    }
    #expect(anchors.part(second) == nil)
}

// testWideWindowIDKept checks that a window id wider than 32 bits, as a Windows HWND can be,
// passes through moor unchanged.
@Test func testWideWindowIDKept() {
    let id: WindowID = 0x100_0000_0000
    let window = WindowInfo(
        id: id, bundle: slack, frame: Frame(x: 900, y: 100, w: 800, h: 600),
        onUltrawide: true, isMain: true)
    let scene = Scene(screen: wide, windows: [window], focused: nil, mouseHeld: false, now: 1000)
    let moves = anchored().moor(scene)
    #expect(moves.count == 1)
    #expect(moves.first?.id == id)
}

// testSlotPartHeld checks that a left half action on a slot window works in the slot, that later
// passes hold the window at that half, and that clearing the part gives it the whole slot again.
@Test func testSlotPartHeld() {
    let anchors = anchored()
    var world = TestWorld()
    let main = world.add(slack, Frame(x: 1500, y: 200, w: 800, h: 600))
    let second = world.add(slack, Frame(x: 2000, y: 300, w: 700, h: 500), main: false)
    world.pass(anchors)
    let area = anchors.actionArea(second, else: anchors.channel(wide))
    #expect(area == leftFull)
    let target = ActionTarget(screens: [wide], areas: [area], index: 0)
    let half = Actions.frame("left-half", cur: world.frame(second), target: target).0
    #expect(half == Frame(x: 0, y: 25, w: 256, h: 1415))
    guard let half else { return }
    #expect(anchors.holdPart(second, "left-half", half))
    #expect(anchors.part(second)?.name == "left-half")
    for _ in 0..<2 {
        world.clock += 1
        world.pass(anchors)
        #expect(world.frame(second) == half)
        #expect(world.frame(main) == leftFull)
    }
    #expect(anchors.clearPart(second))
    #expect(!anchors.clearPart(second))
    world.clock += 1
    world.pass(anchors)
    #expect(world.frame(second) == leftFull)
    #expect(anchors.part(second) == nil)
}

// testSlotPartFreeWindow checks that a window no pin holds gets the area it was given and no part.
@Test func testSlotPartFreeWindow() {
    let anchors = anchored()
    var world = TestWorld()
    let free = world.add("com.apple.TextEdit", Frame(x: 1500, y: 200, w: 800, h: 600))
    world.pass(anchors)
    let channel = anchors.channel(wide)
    #expect(anchors.actionArea(free, else: channel) == channel)
    #expect(!anchors.holdPart(free, "left-half", Frame(x: 512, y: 25, w: 1152, h: 1415)))
    #expect(anchors.part(free) == nil)
}

// testSlotPartPruned checks that a closed window's part is forgotten.
@Test func testSlotPartPruned() {
    let anchors = anchored()
    var world = TestWorld()
    world.add(slack, Frame(x: 1500, y: 200, w: 800, h: 600))
    let second = world.add(slack, Frame(x: 2000, y: 300, w: 700, h: 500), main: false)
    world.pass(anchors)
    #expect(anchors.holdPart(second, "left-half", Frame(x: 0, y: 25, w: 256, h: 1415)))
    anchors.prune(alive: [1])
    #expect(anchors.part(second) == nil)
}

// testNextSlotWindowWraps checks that cycling a slot's windows steps in id order and wraps at both
// ends, and that a free window or a lone holder has no next window.
@Test func testNextSlotWindowWraps() {
    let anchors = anchored()
    var world = TestWorld()
    let main = world.add(slack, Frame(x: 1500, y: 200, w: 800, h: 600))
    let second = world.add(slack, Frame(x: 2000, y: 300, w: 700, h: 500), main: false)
    let third = world.add(slack, Frame(x: 2500, y: 400, w: 600, h: 400), main: false)
    let free = world.add("com.apple.TextEdit", Frame(x: 1500, y: 200, w: 800, h: 600))
    let term = world.add(iterm, Frame(x: 3000, y: 200, w: 800, h: 600))
    world.pass(anchors)
    #expect(anchors.nextSlotWindow(after: main) == second)
    #expect(anchors.nextSlotWindow(after: second) == third)
    #expect(anchors.nextSlotWindow(after: third) == main)
    #expect(anchors.nextSlotWindow(after: main, backward: true) == third)
    #expect(anchors.nextSlotWindow(after: second, backward: true) == main)
    #expect(anchors.nextSlotWindow(after: free) == nil)
    #expect(anchors.nextSlotWindow(after: term) == nil)
}

// finder is the bundle the slot holder scenarios anchor.
let finder = "com.apple.finder"

// testClaimSlotWindow checks that a pin with no holder takes the app's window in its strip over a
// window in the channel listed first, main or not, so the window the owner sees anchored keeps the
// pin, and the channel window stays free.
@Test func testClaimSlotWindow() {
    for slotMain in [false, true] {
        let anchors = Anchors(choices: Choices(slots: [.leftBottom: finder]))
        anchors.choices.slotStacks = false
        var world = TestWorld()
        let free = world.add(finder, Frame(x: 1500, y: 200, w: 800, h: 600), main: !slotMain)
        let slot = world.add(finder, anchors.slotFrame(wide, .leftBottom), main: slotMain)
        world.pass(anchors)
        #expect(anchors.pinned(world.info(slot)), "slot main \(slotMain)")
        #expect(!anchors.pinned(world.info(free)), "slot main \(slotMain)")
        #expect(world.frame(slot) == leftFull, "slot main \(slotMain)")
        #expect(world.frame(free) == Frame(x: 1500, y: 200, w: 800, h: 600), "slot main \(slotMain)")
    }
}

// testClaimAfterTopEmptied checks the owner's sequence: Slack on the left top, Finder on the left
// bottom, Slack closes and the top is set to Empty, and Finder's window takes the whole left side
// while the Finder window in the channel stays free.
@Test func testClaimAfterTopEmptied() {
    let anchors = Anchors(choices: Choices(slots: [.leftTop: slack, .leftBottom: finder]))
    anchors.choices.slotStacks = false
    var world = TestWorld()
    let chat = world.add(slack, Frame(x: 1500, y: 200, w: 800, h: 600))
    let bottom = world.add(finder, Frame(x: 2000, y: 300, w: 800, h: 600))
    world.pass(anchors)
    #expect(world.frame(bottom) == anchors.slotFrame(wide, .leftBottom))
    let other = world.add(finder, Frame(x: 1500, y: 200, w: 800, h: 600))
    world.windows.removeAll { $0.id == chat }
    anchors.choices.slots[.leftTop] = nil
    world.windows[0].isMain = false
    world.windows.swapAt(0, 1)
    world.clock += 1
    world.pass(anchors)
    #expect(world.frame(bottom) == leftFull)
    #expect(anchors.pinned(world.info(bottom)))
    #expect(!anchors.pinned(world.info(other)))
    #expect(world.frame(other) == Frame(x: 1500, y: 200, w: 800, h: 600))
}

// testExtraWindowInStripSettles checks that with slotStacks off a second window of a pinned app
// that opens inside the strip is moved into the channel on the pass that first sees it.
@Test func testExtraWindowInStripSettles() {
    let anchors = Anchors(choices: Choices(slots: [.leftBottom: finder]))
    anchors.choices.slotStacks = false
    var world = TestWorld()
    let holder = world.add(finder, Frame(x: 1500, y: 200, w: 800, h: 600))
    world.pass(anchors)
    #expect(world.frame(holder) == leftFull)
    let extra = world.add(finder, Frame(x: 0, y: 735, w: 400, h: 705), main: false)
    world.clock += 1
    world.pass(anchors)
    #expect(world.frame(holder) == leftFull)
    #expect(!anchors.pinned(world.info(extra)))
    #expect(inChannel(anchors, world.frame(extra)))
}

// weigh lets go of what the pins hold, and the pass after it places them again.
@Test func testWeighLetsGoOfThePins() {
    let anchors = anchored()
    var world = TestWorld()
    let s = world.add(slack, Frame(x: 900, y: 100, w: 800, h: 600))
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
    #expect(!anchors.held.isEmpty && !anchors.holdAreas.isEmpty && !anchors.placed.isEmpty)
    anchors.weigh()
    #expect(anchors.held.isEmpty && anchors.holdAreas.isEmpty && anchors.placed.isEmpty)
    world.pass(anchors)
    #expect(world.frame(s) == leftFull)
    #expect(!anchors.held.isEmpty)
}
