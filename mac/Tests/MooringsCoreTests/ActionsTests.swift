import Testing

@testable import MooringsCore

// laptop is a second screen to the right of the ultrawide.
let laptop = F(5120, 25, 1512, 957)

// desk is the ultrawide with the laptop to its right, acting on the ultrawide's channel.
let desk = ActionTarget(screens: [F(0, 0, 5120, 1440), F(5120, 0, 1512, 982)], areas: [channel, laptop], index: 0)

// Test 0: Screens order left to right, then top to bottom.
@Test func testOrder() {
    let screens = [F(5120, 0, 1920, 1080), F(0, 0, 5120, 1440), F(5120, -1080, 1920, 1080)]
    #expect(Actions.order(screens) == [1, 2, 0])
    #expect(Actions.neighbor(screens, 1, 1) == 2)
    #expect(Actions.neighbor(screens, 0, 1) == 1)
    #expect(Actions.neighbor(screens, 1, -1) == 0)
}

// Test 1: A repeat press on the frame the last press left steps the cycle, and anything else
// starts over.
@Test func testPressCycle() throws {
    let (first, one) = Actions.frame("left-half", cur: window, target: desk)
    #expect(one == 1)
    let landed = try #require(first)
    let (second, two) = Actions.frame("left-half", cur: landed, target: desk, last: LastPress(name: "left-half", press: 1, frame: landed))
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
