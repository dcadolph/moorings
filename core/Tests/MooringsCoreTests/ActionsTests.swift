import Testing

@testable import MooringsCore

// laptop is a second screen to the right of the ultrawide.
let laptop = F(5120, 25, 1512, 957)

// desk is the ultrawide with the laptop to its right, acting on the ultrawide's channel.
let desk = ActionTarget(screens: [F(0, 0, 5120, 1440), F(5120, 0, 1512, 982)], areas: [channel, laptop], index: 0)

// Test 0: By left edge, screens order left to right, then top to bottom.
@Test func testOrder() {
    let screens = [F(5120, 0, 1920, 1080), F(0, 0, 5120, 1440), F(5120, -1080, 1920, 1080)]
    #expect(Actions.order(screens, by: .minX) == [1, 2, 0])
    #expect(Actions.neighbor(screens, 1, 1, by: .minX) == 2)
    #expect(Actions.neighbor(screens, 0, 1, by: .minX) == 1)
    #expect(Actions.neighbor(screens, 1, -1, by: .minX) == 0)
}

// Test 8: The default puts a row above another first and keeps one row left to right, and midX
// orders by center.
@Test func testOrderRows() {
    let stacked = [F(5120, 0, 1920, 1080), F(0, 0, 5120, 1440), F(5120, -1080, 1920, 1080)]
    #expect(Actions.order(stacked) == [2, 1, 0])
    let row = [F(5120, 0, 1512, 982), F(0, 0, 5120, 1440), F(-1920, 200, 1920, 1080)]
    #expect(Actions.order(row) == [2, 1, 0])
    #expect(Actions.order(row) == Actions.order(row, by: .minX))
    let wide = [F(0, 0, 5120, 1440), F(1000, -1080, 1920, 1080)]
    #expect(Actions.order(wide, by: .midX) == [1, 0])
    #expect(Actions.order(wide, by: .minX) == [0, 1])
}

// Test 1: A repeat press on the frame the last press left steps the cycle, and anything else
// starts over.
@Test func testPressCycle() throws {
    let (first, one, _) = Actions.frame("left-half", cur: window, target: desk)
    #expect(one == 1)
    let landed = try #require(first)
    let (second, two, _) = Actions.frame("left-half", cur: landed, target: desk, last: LastPress(name: "left-half", press: 1, frame: landed))
    #expect(two == 2)
    #expect(second == F(512, 25, 1536, 1415))
    let drifted = F(landed.x + 3, landed.y, landed.w, landed.h)
    #expect(Actions.frame("left-half", cur: drifted, target: desk, last: LastPress(name: "left-half", press: 1, frame: landed)).press == 1)
    #expect(Actions.frame("right-half", cur: landed, target: desk, last: LastPress(name: "left-half", press: 1, frame: landed)).press == 1)
}

// Test 2: Display moves carry the relative frame to the neighbor, and do nothing on one screen.
@Test func testDisplayMove() throws {
    let half = try #require(Geometry.position("left-half", channel))
    #expect(Actions.frame("next-display", cur: half, target: desk).0 == F(5120, 25, 756, 957))
    #expect(Actions.frame("previous-display", cur: half, target: desk).0 == F(5120, 25, 756, 957))
    let alone = ActionTarget(screens: [F(0, 0, 5120, 1440)], areas: [channel], index: 0)
    #expect(Actions.frame("next-display", cur: half, target: alone).0 == nil)
}

// Test 3: Larger and smaller step 30 points.
@Test func testLargerSmaller() {
    #expect(Actions.frame("larger", cur: window, target: desk).0 == F(570, 70, 1060, 860))
    #expect(Actions.frame("smaller", cur: window, target: desk).0 == F(630, 130, 940, 740))
}

// Test 4: A custom size uses its spec, and an unknown one returns nil.
@Test func testCustomSize() {
    let sizes = ["size:Middle": CustomSpec(x: 0.25, w: 0.5)]
    #expect(Actions.frame("size:Middle", cur: window, target: desk, sizes: sizes).0 == F(1088, 25, 1152, 1415))
    #expect(Actions.frame("size:Gone", cur: window, target: desk, sizes: sizes).0 == nil)
}

// Test 5: The gap reaches the geometry.
@Test func testActionGap() {
    #expect(Actions.frame("left-half", cur: window, target: desk, gap: 10).0 == F(522, 35, 1137, 1395))
}

// Test 6: Specified centers 1680 by 1050 points, shrinks to fit a smaller area, honors the gap, and
// reads its size from the behaviors.
@Test func testSpecified() {
    var b = Behaviors()
    b.specifiedWidth = 800
    b.specifiedHeight = 600
    #expect(Actions.frame("specified", cur: window, target: desk, behavior: b).0 == F(1264, 433, 800, 600))
    #expect(Actions.frame("specified", cur: window, target: desk).0 == F(824, 208, 1680, 1050))
    let small = ActionTarget(screens: [F(0, 0, 1500, 900)], areas: [F(0, 25, 1500, 875)], index: 0)
    #expect(Actions.frame("specified", cur: window, target: small).0 == F(0, 25, 1500, 875))
    let mid = ActionTarget(screens: [F(0, 0, 1600, 1000)], areas: [F(0, 0, 1600, 1000)], index: 0)
    #expect(Actions.frame("specified", cur: window, target: mid).0 == F(0, 0, 1600, 1000))
    #expect(Actions.frame("specified", cur: window, target: desk, gap: 10).0 == F(824, 208, 1680, 1050))
    #expect(Actions.frame("specified", cur: window, target: mid, gap: 10).0 == F(10, 10, 1580, 980))
}

// Test 7: Display-N picks the Nth screen in left to right order, and is nil for a missing or
// current display.
@Test func testSpecificDisplay() throws {
    let screens = [F(5120, 0, 1920, 1080), F(0, 0, 5120, 1440), F(6000, 0, 1000, 800)]
    let areas = [F(5120, 25, 1920, 1055), channel, F(6000, 0, 1000, 800)]
    let from = ActionTarget(screens: screens, areas: areas, index: 1)
    let half = try #require(Geometry.position("left-half", channel))
    #expect(Actions.frame("display-two", cur: half, target: from).0
        == Geometry.transfer(half, from: channel, to: areas[0]))
    #expect(Actions.frame("display-two", cur: half, target: from).0 != nil)
    #expect(Actions.frame("display-three", cur: half, target: from).0
        == Geometry.transfer(half, from: channel, to: areas[2]))
    #expect(Actions.frame("display-one", cur: half, target: from).0 == nil)
    #expect(Actions.frame("display-four", cur: half, target: from).0 == nil)
    #expect(Actions.frame("display-nine", cur: half, target: from).0 == nil)
}

// twoUp is the laptop left of a second screen, for repeat presses that leave the display.
private let twoUp = ActionTarget(screens: [F(0, 0, 1512, 982), F(1512, 0, 1920, 1080)],
                                 areas: [F(0, 25, 1512, 957), F(1512, 0, 1920, 1080)], index: 0)

// repeated returns behaviors that do mode on a repeat press.
private func repeated(_ mode: SubsequentExecution) -> Behaviors {
    var b = Behaviors()
    b.subsequentExecution = mode
    return b
}

// press runs name on cur with last as the previous press and returns the result as a LastPress.
private func press(
    _ name: String, _ cur: Frame, _ target: ActionTarget, _ b: Behaviors, after last: LastPress? = nil
) throws -> LastPress {
    let (f, n, as_) = Actions.frame(name, cur: cur, target: target, last: last, behavior: b)
    return LastPress(name: as_, press: n, frame: try #require(f))
}

// Test 9: Traverse sends a right half on to the next display's left half, which then counts as a
// left half, and wraps past the last display.
@Test func testTraverse() throws {
    let b = repeated(.traverseDisplays)
    let one = try press("right-half", window, twoUp, b)
    #expect(one.frame == Geometry.position("right-half", twoUp.areas[0]))
    let two = try press("right-half", one.frame, twoUp, b, after: one)
    #expect(two.name == "left-half")
    #expect(two.press == 1)
    #expect(two.frame == Geometry.position("left-half", twoUp.areas[1]))
    let on = ActionTarget(screens: twoUp.screens, areas: twoUp.areas, index: 1)
    let three = try press("right-half", two.frame, on, b, after: two)
    #expect(three.frame == Geometry.position("right-half", twoUp.areas[1]))
    let four = try press("right-half", three.frame, on, b, after: three)
    #expect(four.frame == Geometry.position("left-half", twoUp.areas[0]))
}

// Test 10: Traverse and cycle cycles sizes where traverse would wrap, and every mode leaves a top
// half alone except cycle sizes.
@Test func testTraverseAndCycle() throws {
    let b = repeated(.traverseAndCycle)
    let one = try press("left-half", window, twoUp, b)
    let two = try press("left-half", one.frame, twoUp, b, after: one)
    #expect(two.name == "left-half")
    #expect(two.frame == Geometry.cycle("left-half", 2, twoUp.areas[0]))
    let top = try press("top-half", window, twoUp, repeated(.traverseDisplays))
    let again = try press("top-half", top.frame, twoUp, repeated(.traverseDisplays), after: top)
    #expect(again.frame == top.frame)
}

// Test 11: Switch sides flips a half each press, and none places the same frame again.
@Test func testSwitchSidesAndNone() throws {
    let b = repeated(.switchSides)
    let one = try press("top-half", window, desk, b)
    let two = try press("top-half", one.frame, desk, b, after: one)
    #expect(two.name == "bottom-half")
    #expect(two.frame == Geometry.position("bottom-half", channel))
    let three = try press("top-half", two.frame, desk, b, after: two)
    #expect(three.frame == one.frame)
    let still = try press("left-half", window, desk, repeated(.none))
    let pressed = try press("left-half", still.frame, desk, repeated(.none), after: still)
    #expect(pressed.frame == still.frame)
    #expect(pressed.press == 1)
}

// Test 12: Cycle quadrants steps a corner across, down, and back, and cycles sizes elsewhere.
@Test func testCycleQuadrants() throws {
    let b = repeated(.cycleQuadrants)
    var last = try press("top-left", window, desk, b)
    var seen = [last.frame]
    for _ in 0 ..< 4 {
        last = try press("top-left", last.frame, desk, b, after: last)
        #expect(last.name == "top-left")
        seen.append(last.frame)
    }
    let want = ["top-left", "top-right", "bottom-left", "bottom-right", "top-left"].map {
        Geometry.position($0, channel)
    }
    #expect(seen == want)
    let half = try press("left-half", window, desk, b)
    #expect(try press("left-half", half.frame, desk, b, after: half).frame == Geometry.cycle("left-half", 2, channel))
}

// Test 13: Cycle displays places the same action on the next display and keeps counting presses.
@Test func testCycleDisplays() throws {
    let b = repeated(.cycleDisplays)
    let one = try press("left-half", window, twoUp, b)
    let two = try press("left-half", one.frame, twoUp, b, after: one)
    #expect(two.name == "left-half")
    #expect(two.press == 2)
    #expect(two.frame == Geometry.position("left-half", twoUp.areas[1]))
}

// Test 14: Edge gaps shrink the area, skip other screens when on the main screen only, and skip
// maximize when they do not apply to it.
@Test func testEdgeGaps() {
    var b = Behaviors()
    b.screenEdgeGapLeft = 20
    b.screenEdgeGapTop = 10
    #expect(Actions.frame("left-half", cur: window, target: twoUp, behavior: b).0 == F(20, 35, 746, 947))
    #expect(Actions.frame("maximize", cur: window, target: twoUp, behavior: b).0 == F(20, 35, 1492, 947))
    b.applyGapsToMaximize = false
    #expect(Actions.frame("maximize", cur: window, target: twoUp, behavior: b).0 == twoUp.areas[0])
    b.gapsOnMainOnly = true
    let second = ActionTarget(screens: twoUp.screens, areas: twoUp.areas, index: 1)
    #expect(Actions.frame("left-half", cur: window, target: second, behavior: b).0 == F(1512, 0, 960, 1080))
    let notched = ActionTarget(screens: twoUp.screens, areas: twoUp.areas, index: 0, notched: [0])
    b.screenEdgeGapTopNotch = 0
    #expect(Actions.frame("left-half", cur: window, target: notched, behavior: b).0 == F(20, 25, 746, 957))
}

// Test 15: The Stage Manager strip comes off an area at the strip's screen edge only, so the
// ultrawide channel between anchored strips keeps its width.
@Test func testStage() {
    let staged = ActionTarget(screens: twoUp.screens, areas: twoUp.areas, index: 0, staged: [0])
    #expect(Actions.frame("maximize", cur: window, target: staged).0 == F(190, 25, 1322, 957))
    let right = ActionTarget(screens: twoUp.screens, areas: twoUp.areas, index: 0, staged: [0], stageOnRight: true)
    #expect(Actions.frame("maximize", cur: window, target: right).0 == F(0, 25, 1322, 957))
    let wide = ActionTarget(screens: desk.screens, areas: desk.areas, index: 0, staged: [0])
    #expect(Actions.frame("maximize", cur: window, target: wide).0 == channel)
    #expect(Actions.frame("maximize", cur: window, target: twoUp).0 == twoUp.areas[0])
    let other = ActionTarget(screens: twoUp.screens, areas: twoUp.areas, index: 0, staged: [1])
    #expect(Actions.frame("maximize", cur: window, target: other).0 == twoUp.areas[0])
}

// oneDisplay is a single 1000 by 800 display for the arrow tests.
let oneDisplay = ActionTarget(screens: [F(0, 0, 1000, 800)], areas: [F(0, 0, 1000, 800)], index: 0)

// sideBySide is two 1000 by 800 displays, the window on the left one.
let sideBySide = ActionTarget(
    screens: [F(0, 0, 1000, 800), F(1000, 0, 1000, 800)], areas: [F(0, 0, 1000, 800), F(1000, 0, 1000, 800)], index: 0)

// arrowFrame returns the frame of action name on target t for the arrow tests.
func arrowFrame(_ name: String, _ t: ActionTarget) -> Frame {
    Actions.frame(name, cur: F(100, 100, 300, 300), target: t).0!
}

// secondDisplay is sideBySide with the window on the right display.
let secondDisplay = ActionTarget(screens: sideBySide.screens, areas: sideBySide.areas, index: 1)

// Test: Arrow left from a free window or maximize takes the left half, and the right side goes left.
@Test func testArrowLeft() {
    let free = F(100, 100, 300, 300)
    #expect(Actions.arrow("arrow-left", cur: free, target: oneDisplay)
        == .frame(arrowFrame("left-half", oneDisplay), name: "left-half"))
    #expect(Actions.arrow("arrow-left", cur: arrowFrame("maximize", oneDisplay), target: oneDisplay)
        == .frame(arrowFrame("left-half", oneDisplay), name: "left-half"))
    #expect(Actions.arrow("arrow-left", cur: arrowFrame("right-half", oneDisplay), target: oneDisplay)
        == .frame(arrowFrame("left-half", oneDisplay), name: "left-half"))
    #expect(Actions.arrow("arrow-left", cur: arrowFrame("top-right", oneDisplay), target: oneDisplay)
        == .frame(arrowFrame("top-left", oneDisplay), name: "top-left"))
    #expect(Actions.arrow("arrow-left", cur: arrowFrame("bottom-right", oneDisplay), target: oneDisplay)
        == .frame(arrowFrame("bottom-left", oneDisplay), name: "bottom-left"))
    for name in ["left-half", "top-left", "bottom-left"] {
        #expect(Actions.arrow("arrow-left", cur: arrowFrame(name, oneDisplay), target: oneDisplay) == .stay)
    }
    let toRight = [("left-half", "right-half"), ("top-left", "top-right"), ("bottom-left", "bottom-right")]
    for (from, to) in toRight {
        #expect(Actions.arrow("arrow-left", cur: arrowFrame(from, sideBySide), target: sideBySide)
            == .frame(arrowFrame(to, secondDisplay), name: to), "\(from) wraps to \(to)")
    }
}

// Test: Arrow right mirrors arrow left, crossing to the next display from the right side.
@Test func testArrowRight() {
    let free = F(100, 100, 300, 300)
    #expect(Actions.arrow("arrow-right", cur: free, target: oneDisplay)
        == .frame(arrowFrame("right-half", oneDisplay), name: "right-half"))
    #expect(Actions.arrow("arrow-right", cur: arrowFrame("maximize", oneDisplay), target: oneDisplay)
        == .frame(arrowFrame("right-half", oneDisplay), name: "right-half"))
    #expect(Actions.arrow("arrow-right", cur: arrowFrame("left-half", oneDisplay), target: oneDisplay)
        == .frame(arrowFrame("right-half", oneDisplay), name: "right-half"))
    #expect(Actions.arrow("arrow-right", cur: arrowFrame("top-left", oneDisplay), target: oneDisplay)
        == .frame(arrowFrame("top-right", oneDisplay), name: "top-right"))
    #expect(Actions.arrow("arrow-right", cur: arrowFrame("bottom-left", oneDisplay), target: oneDisplay)
        == .frame(arrowFrame("bottom-right", oneDisplay), name: "bottom-right"))
    for name in ["right-half", "top-right", "bottom-right"] {
        #expect(Actions.arrow("arrow-right", cur: arrowFrame(name, oneDisplay), target: oneDisplay) == .stay)
    }
    let toLeft = [("right-half", "left-half"), ("top-right", "top-left"), ("bottom-right", "bottom-left")]
    for (from, to) in toLeft {
        #expect(Actions.arrow("arrow-right", cur: arrowFrame(from, secondDisplay), target: secondDisplay)
            == .frame(arrowFrame(to, sideBySide), name: to), "\(from) wraps to \(to)")
    }
}

// Test: Arrow up maximizes a free window, raises halves and bottom quarters, lowers top quarters to halves.
@Test func testArrowUp() {
    let t = oneDisplay
    #expect(Actions.arrow("arrow-up", cur: F(100, 100, 300, 300), target: t)
        == .frame(arrowFrame("maximize", t), name: "maximize"))
    #expect(Actions.arrow("arrow-up", cur: arrowFrame("maximize", t), target: t) == .stay)
    let table = [
        ("left-half", "top-left"), ("right-half", "top-right"), ("bottom-left", "top-left"),
        ("bottom-right", "top-right"), ("top-left", "left-half"), ("top-right", "right-half"),
    ]
    for (from, to) in table {
        #expect(Actions.arrow("arrow-up", cur: arrowFrame(from, t), target: t)
            == .frame(arrowFrame(to, t), name: to), "\(from) to \(to)")
    }
}

// Test: Arrow down restores a maximized window, lowers halves and top quarters, and minimizes a free window.
@Test func testArrowDown() {
    let t = oneDisplay
    #expect(Actions.arrow("arrow-down", cur: arrowFrame("maximize", t), target: t) == .restore)
    #expect(Actions.arrow("arrow-down", cur: F(100, 100, 300, 300), target: t) == .minimize)
    let table = [
        ("left-half", "bottom-left"), ("right-half", "bottom-right"), ("top-left", "bottom-left"),
        ("top-right", "bottom-right"), ("bottom-left", "left-half"), ("bottom-right", "right-half"),
    ]
    for (from, to) in table {
        #expect(Actions.arrow("arrow-down", cur: arrowFrame(from, t), target: t)
            == .frame(arrowFrame(to, t), name: to), "\(from) to \(to)")
    }
}

// Test: From a free window Left, Up, Down, Down walks left-half, top-left, bottom-left, left-half.
@Test func testArrowWalk() {
    var cur = F(100, 100, 300, 300)
    for (arrow, want) in [
        ("arrow-left", "left-half"), ("arrow-up", "top-left"), ("arrow-down", "bottom-left"),
        ("arrow-down", "left-half"),
    ] {
        guard case let .frame(f, name) = Actions.arrow(arrow, cur: cur, target: oneDisplay) else {
            Issue.record("\(arrow) gave no frame")
            return
        }
        #expect(name == want)
        #expect(f == arrowFrame(want, oneDisplay))
        cur = f
    }
}

// Test: An unknown arrow name does nothing.
@Test func testArrowUnknown() {
    #expect(Actions.arrow("arrow-sideways", cur: F(100, 100, 300, 300), target: oneDisplay) == .stay)
}

// plain is one 1000 by 800 screen whose whole area is usable.
let plain = ActionTarget(screens: [F(0, 0, 1000, 800)], areas: [F(0, 0, 1000, 800)], index: 0)

// Swift only: halvesPreserveOtherAxis keeps the window's height on a side half and its width on a top half.
@Test func testHalvesPreserveOtherAxis() {
    let cur = F(100, 100, 400, 300)
    var b = Behaviors()
    #expect(Actions.frame("left-half", cur: cur, target: plain, behavior: b).0 == F(0, 0, 500, 800))
    b.halvesPreserveOtherAxis = true
    #expect(Actions.frame("left-half", cur: cur, target: plain, behavior: b).0 == F(0, 100, 500, 300))
    #expect(Actions.frame("top-half", cur: cur, target: plain, behavior: b).0 == F(100, 0, 400, 400))
    #expect(Actions.frame("maximize", cur: cur, target: plain, behavior: b).0 == F(0, 0, 1000, 800))
    #expect(Behavior.keepOtherAxis("left-half", F(0, 0, 500, 800), cur: F(0, 700, 10, 900), area: plain.areas[0])
        == F(0, 0, 500, 800))
}

// Swift only: centerHalfCycles steps center half through two thirds and one third on repeat.
@Test func testCenterHalfCycles() {
    let half = Geometry.position("center-half", plain.areas[0])!
    let last = LastPress(name: "center-half", press: 1, frame: half)
    var b = Behaviors()
    #expect(Actions.frame("center-half", cur: half, target: plain, last: last, behavior: b).0 == half)
    b.centerHalfCycles = true
    let two = Actions.frame("center-half", cur: half, target: plain, last: last, behavior: b)
    #expect(two.0 == Geometry.position("center-two-thirds", plain.areas[0]))
    #expect(two.press == 2)
    let three = LastPress(name: "center-half", press: 2, frame: two.0!)
    #expect(Actions.frame("center-half", cur: two.0!, target: plain, last: three, behavior: b).0
        == Geometry.position("center-third", plain.areas[0]))
}

// Swift only: the minimum window size floors smaller and halve at its share of the area.
@Test func testMinimumWindowSize() {
    var b = Behaviors()
    let wide = F(0, 0, 400, 800)
    #expect(Actions.frame("halve-width-left", cur: wide, target: plain, behavior: b).0 == wide)
    let box = F(100, 100, 300, 300)
    #expect(Actions.frame("smaller", cur: box, target: plain, behavior: b).0 == F(100, 130, 300, 240))
    b.minimumWindowWidth = 0.1
    b.minimumWindowHeight = 0.1
    #expect(Actions.frame("halve-width-left", cur: wide, target: plain, behavior: b).0 == F(0, 0, 200, 800))
    #expect(Actions.frame("smaller", cur: box, target: plain, behavior: b).0 == F(130, 130, 240, 240))
    #expect(Actions.frame("smaller-height", cur: F(0, 0, 1000, 100), target: plain, behavior: b).0
        == F(0, 0, 1000, 100))
}

// Swift only: maximize pressed again restores only when the choice is on and the window has not moved.
@Test func testRestoresMaximize() {
    let full = F(0, 0, 1000, 800)
    let last = LastPress(name: "maximize", press: 1, frame: full)
    var b = Behaviors()
    #expect(!Behavior.restoresMaximize("maximize", cur: full, last: last, b))
    b.repeatedMaximizeRestores = true
    #expect(Behavior.restoresMaximize("maximize", cur: full, last: last, b))
    #expect(!Behavior.restoresMaximize("maximize", cur: F(0, 0, 900, 800), last: last, b))
    #expect(!Behavior.restoresMaximize("left-half", cur: full, last: last, b))
    #expect(!Behavior.restoresMaximize("maximize", cur: full, last: nil, b))
}

// Test 16: A resize an app stops above the asked size on the way down kept a minimum, and a window
// that did not resize, grew past its start, or landed elsewhere did not.
@Test func testKeptMinimum() {
    let start = F(100, 100, 1400, 1000)
    let asked = F(40, 40, 900, 600)
    #expect(Actions.keptMinimum(start: start, asked: asked, got: F(40, 40, 900, 652)))
    #expect(Actions.keptMinimum(start: start, asked: asked, got: F(40, 40, 1000, 700)))
    #expect(!Actions.keptMinimum(start: start, asked: asked, got: asked))
    #expect(!Actions.keptMinimum(start: start, asked: asked, got: F(40, 40, 1400, 1000)))
    #expect(!Actions.keptMinimum(start: start, asked: asked, got: F(40, 40, 900, 1100)))
    #expect(!Actions.keptMinimum(start: start, asked: asked, got: F(40, 40, 800, 652)))
    #expect(!Actions.keptMinimum(start: start, asked: asked, got: F(300, 40, 900, 652)))
}
