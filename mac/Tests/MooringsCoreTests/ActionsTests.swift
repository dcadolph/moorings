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
