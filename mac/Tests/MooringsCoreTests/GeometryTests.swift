import Testing

@testable import MooringsCore

// F builds a frame tersely for test tables.
func F(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Frame {
    Frame(x: x, y: y, w: w, h: h)
}

// inside reports whether f lies within area.
func inside(_ f: Frame, _ area: Frame) -> Bool {
    f.x >= area.x && f.y >= area.y && f.w > 0 && f.h > 0
        && f.x + f.w <= area.x + area.w && f.y + f.h <= area.y + area.h
}

// channel is the default channel of a 5120 by 1440 ultrawide.
let channel = F(512, 25, 2304, 1415)
// tall is a portrait area.
let tall = F(0, 25, 1080, 1895)
// window is a frame that fits inside channel.
let window = F(600, 100, 1000, 800)
// screen is the ultrawide's visible frame below the menu bar.
let screen = F(0, 25, 5120, 1415)

// PositionCase is one named position expectation.
struct PositionCase: Sendable, CustomTestStringConvertible {
    // Name is the action name.
    let name: String
    // Area is the work area.
    let area: Frame
    // Cur is the window's current frame.
    let cur: Frame?
    // Gap is the gap in points.
    let gap: Double
    // WantFrame is the expected frame.
    let wantFrame: Frame

    // testDescription labels the case in test output.
    var testDescription: String { "\(name) gap \(gap)" }
}

// positionCases mirrors the fixed frames of geometry_test.lua tests 0 to 11.
let positionCases: [PositionCase] = [
    PositionCase(name: "left-half", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1152, 1415)), // Test 0: Left half.
    PositionCase(name: "right-half", area: channel, cur: nil, gap: 0, wantFrame: F(1664, 25, 1152, 1415)), // Test 0: Right half.
    PositionCase(name: "top-half", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 2304, 707)), // Test 0: Top half.
    PositionCase(name: "bottom-half", area: channel, cur: nil, gap: 0, wantFrame: F(512, 732, 2304, 708)), // Test 0: Bottom half.
    PositionCase(name: "center-half", area: channel, cur: nil, gap: 0, wantFrame: F(1088, 25, 1152, 1415)), // Test 0: Center half.
    PositionCase(name: "top-left", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1152, 707)), // Test 1: Top left.
    PositionCase(name: "bottom-right", area: channel, cur: nil, gap: 0, wantFrame: F(1664, 732, 1152, 708)), // Test 1: Bottom right.
    PositionCase(name: "first-third", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 768, 1415)), // Test 2: First third.
    PositionCase(name: "first-two-thirds", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1536, 1415)), // Test 2: First two.
    PositionCase(name: "last-two-thirds", area: channel, cur: nil, gap: 0, wantFrame: F(1280, 25, 1536, 1415)), // Test 2: Last two.
    PositionCase(name: "center-two-thirds", area: channel, cur: nil, gap: 0, wantFrame: F(896, 25, 1536, 1415)), // Test 2: Center two.
    PositionCase(name: "first-third", area: tall, cur: nil, gap: 0, wantFrame: F(0, 25, 1080, 631)), // Test 3: Tall first third.
    PositionCase(name: "last-fourth", area: tall, cur: nil, gap: 0, wantFrame: F(0, 1446, 1080, 474)), // Test 3: Tall last fourth.
    PositionCase(name: "left-half", area: tall, cur: nil, gap: 0, wantFrame: F(0, 25, 540, 1895)), // Test 3: Halves stay.
    PositionCase(name: "top-left-third", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1536, 707)), // Test 4: Wide TL.
    PositionCase(name: "bottom-right-third", area: channel, cur: nil, gap: 0, wantFrame: F(1280, 732, 1536, 708)), // Test 4: Wide BR.
    PositionCase(name: "top-right-third", area: tall, cur: nil, gap: 0, wantFrame: F(540, 25, 540, 1263)), // Test 4: Tall TR.
    PositionCase(name: "bottom-left-third", area: tall, cur: nil, gap: 0, wantFrame: F(0, 656, 540, 1264)), // Test 4: Tall BL.
    PositionCase(name: "first-three-fourths", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1728, 1415)), // Test 5: First three.
    PositionCase(name: "last-three-fourths", area: channel, cur: nil, gap: 0, wantFrame: F(1088, 25, 1728, 1415)), // Test 5: Last three.
    PositionCase(name: "center-three-fourths", area: channel, cur: nil, gap: 0, wantFrame: F(800, 25, 1728, 1415)), // Test 5: Center three.
    PositionCase(name: "middle-center-ninth", area: channel, cur: nil, gap: 0, wantFrame: F(1280, 496, 768, 472)), // Test 6: Ninth.
    PositionCase(name: "top-center-right-eighth", area: channel, cur: nil, gap: 0, wantFrame: F(1664, 25, 576, 707)), // Test 6: Eighth.
    PositionCase(name: "left-half", area: channel, cur: nil, gap: 10, wantFrame: F(522, 35, 1137, 1395)), // Test 7: Gap left.
    PositionCase(name: "right-half", area: channel, cur: nil, gap: 10, wantFrame: F(1669, 35, 1137, 1395)), // Test 7: Gap right.
    PositionCase(name: "maximize", area: channel, cur: window, gap: 10, wantFrame: F(522, 35, 2284, 1395)), // Test 7: Gap maximize.
    PositionCase(name: "maximize", area: channel, cur: window, gap: 0, wantFrame: channel), // Test 8: Maximize.
    PositionCase(name: "almost-maximize", area: channel, cur: window, gap: 0, wantFrame: F(627, 96, 2074, 1274)), // Test 8: Almost.
    PositionCase(name: "maximize-height", area: channel, cur: window, gap: 0, wantFrame: F(600, 25, 1000, 1415)), // Test 8: Height.
    PositionCase(name: "maximize-height", area: channel, cur: window, gap: 10, wantFrame: F(600, 35, 1000, 1395)), // Test 8: Height gap.
    PositionCase(name: "center", area: channel, cur: window, gap: 0, wantFrame: F(1164, 333, 1000, 800)), // Test 9: Center.
    PositionCase(name: "center", area: channel, cur: F(0, 0, 3000, 800), gap: 0, wantFrame: F(512, 333, 2304, 800)), // Test 9: Wide.
    PositionCase(name: "center", area: channel, cur: F(0, 0, 1000, 2000), gap: 0, wantFrame: F(1164, 25, 1000, 1415)), // Test 9: Tall.
    PositionCase(name: "center-prominently", area: channel, cur: window, gap: 0, wantFrame: F(1164, 179, 1000, 800)), // Test 10: Prominent.
    PositionCase(name: "move-left", area: channel, cur: window, gap: 0, wantFrame: F(512, 333, 1000, 800)), // Test 11: Move left.
    PositionCase(name: "move-right", area: channel, cur: window, gap: 0, wantFrame: F(1816, 333, 1000, 800)), // Test 11: Move right.
    PositionCase(name: "move-up", area: channel, cur: window, gap: 0, wantFrame: F(1164, 25, 1000, 800)), // Test 11: Move up.
    PositionCase(name: "move-down", area: channel, cur: window, gap: 0, wantFrame: F(1164, 640, 1000, 800)), // Test 11: Move down.
]

// testPosition checks each named position against the Lua frames.
@Test(arguments: positionCases)
func testPosition(test: PositionCase) {
    #expect(Geometry.position(test.name, test.area, test.cur, gap: test.gap) == test.wantFrame)
}

// Test 2: Thirds tile the width on a wide area.
@Test func testThirdsTile() throws {
    let a = try #require(Geometry.position("first-third", channel))
    let b = try #require(Geometry.position("center-third", channel))
    let c = try #require(Geometry.position("last-third", channel))
    #expect(a.x + a.w == b.x)
    #expect(b.x + b.w == c.x)
    #expect(c.x + c.w == channel.x + channel.w)
}

// Test 5: Fourths tile the width.
@Test func testFourthsTile() throws {
    var x = channel.x
    for name in ["first-fourth", "second-fourth", "third-fourth", "last-fourth"] {
        let f = try #require(Geometry.position(name, channel))
        #expect(f.x == x && f.w == 576, "\(name) \(f)")
        x = f.x + f.w
    }
}

// Test 6: Sixths, ninths and eighths cover the area with no overlap.
@Test(arguments: [("sixth", 6), ("ninth", 9), ("eighth", 8)])
func testGridCover(suffix: String, wantCount: Int) throws {
    var total = 0.0
    var count = 0
    for name in Geometry.names() where name.hasSuffix("-\(suffix)") {
        let f = try #require(Geometry.position(name, channel))
        #expect(inside(f, channel), "\(name) \(f)")
        total += f.w * f.h
        count += 1
    }
    #expect(count == wantCount)
    #expect(total == channel.w * channel.h)
}

// Test 7: A gap leaves the gap between neighbors and at the area edge, odd gaps included.
@Test func testGapBetween() throws {
    let l = try #require(Geometry.position("left-half", channel, gap: 10))
    let r = try #require(Geometry.position("right-half", channel, gap: 10))
    #expect(r.x - (l.x + l.w) == 10)
    #expect(channel.x + channel.w - (r.x + r.w) == 10)
    let oddL = try #require(Geometry.position("left-half", channel, gap: 7))
    let oddR = try #require(Geometry.position("right-half", channel, gap: 7))
    #expect(oddR.x - (oddL.x + oddL.w) == 7)
}

// Test 12: Every name returns a frame inside the area, and unknown names return nil.
@Test func testAllNames() {
    for name in Geometry.names() {
        let f = Geometry.position(name, channel, window)
        #expect(f.map { inside($0, channel) } == true, "\(name) \(String(describing: f))")
    }
    #expect(Geometry.position("sideways", channel, window) == nil)
    #expect(Geometry.names().count == 58)
}

// Test 13: Edge, slot, regions and clamp keep their v2 results.
@Test func testStrips() {
    #expect(Geometry.edge(screen, .right, 45) == F(2816, 25, 2304, 1415))
    #expect(Geometry.slot(screen, .left, .bottom, 10) == F(0, 732, 512, 708))
    #expect(Geometry.regions(screen, 10, 45).channel == channel)
    #expect(Geometry.clamp(F(0, 0, 3000, 500), channel) == F(512, 25, 2304, 500))
}

// Test 14: Halves cycle their width 1/2, 2/3, 1/3 and wrap, and thirds walk the area.
@Test func testCycle() {
    let half = F(512, 25, 1152, 1415)
    #expect(Geometry.cycle("left-half", 1, channel) == half)
    #expect(Geometry.cycle("left-half", 2, channel) == F(512, 25, 1536, 1415))
    #expect(Geometry.cycle("left-half", 3, channel) == F(512, 25, 768, 1415))
    #expect(Geometry.cycle("left-half", 4, channel) == half)
    #expect(Geometry.cycle("right-half", 2, channel) == F(1280, 25, 1536, 1415))
    #expect(Geometry.cycle("right-half", 3, channel) == F(2048, 25, 768, 1415))
    #expect(Geometry.cycle("first-third", 2, channel) == Geometry.position("center-third", channel))
    #expect(Geometry.cycle("first-third", 3, channel) == Geometry.position("last-third", channel))
    #expect(Geometry.cycle("last-third", 2, channel) == Geometry.position("center-third", channel))
    #expect(Geometry.cycle("last-third", 3, channel) == Geometry.position("first-third", channel))
    #expect(Geometry.cycle("left-half", 2, tall) == F(0, 25, 720, 1895))
    #expect(Geometry.cycle("maximize", 5, channel, window) == channel)
    #expect(Geometry.cycle("sideways", 1, channel, window) == nil)
}

// ResizeCase is one resize expectation.
struct ResizeCase: Sendable, CustomTestStringConvertible {
    // Cur is the window's current frame.
    let cur: Frame
    // D is the step in points.
    let d: Double
    // WantFrame is the expected frame.
    let wantFrame: Frame

    // testDescription labels the case in test output.
    var testDescription: String { "\(cur) by \(d)" }
}

// resizeCases mirrors geometry_test.lua test 15.
let resizeCases: [ResizeCase] = [
    ResizeCase(cur: window, d: 30, wantFrame: F(570, 70, 1060, 860)), // Test 15: Larger.
    ResizeCase(cur: window, d: -30, wantFrame: F(630, 130, 940, 740)), // Test 15: Smaller.
    ResizeCase(cur: F(512, 25, 1152, 1415), d: 30, wantFrame: F(512, 25, 1182, 1415)), // Test 15: Larger curtain.
    ResizeCase(cur: F(512, 25, 1152, 1415), d: -30, wantFrame: F(512, 55, 1122, 1355)), // Test 15: Smaller curtain.
    ResizeCase(cur: channel, d: -30, wantFrame: F(542, 55, 2244, 1355)), // Test 15: Smaller full.
    ResizeCase(cur: channel, d: 30, wantFrame: channel), // Test 15: Larger full.
    ResizeCase(cur: F(530, 100, 1000, 800), d: 30, wantFrame: F(512, 70, 1048, 860)), // Test 15: Stops at edge.
    ResizeCase(cur: F(600, 100, 600, 800), d: -30, wantFrame: F(600, 130, 600, 740)), // Test 15: Smaller floor.
    ResizeCase(cur: F(0, 0, 3000, 500), d: 30, wantFrame: F(512, 25, 2304, 530)), // Test 15: Clamped first.
]

// testResize checks larger and smaller against the Lua frames.
@Test(arguments: resizeCases)
func testResize(test: ResizeCase) {
    #expect(Geometry.resize(channel, test.cur, test.d) == test.wantFrame)
}

// Test 16: Transfer keeps the relative frame across areas of different sizes.
@Test func testTransfer() throws {
    let laptop = F(5120, 25, 1512, 957)
    let half = try #require(Geometry.position("left-half", channel))
    let moved = Geometry.transfer(half, from: channel, to: laptop)
    #expect(moved == F(5120, 25, 756, 957))
    #expect(Geometry.transfer(moved, from: laptop, to: channel) == half)
    let right = try #require(Geometry.position("right-half", channel))
    #expect(Geometry.transfer(right, from: channel, to: laptop) == F(5876, 25, 756, 957))
    #expect(inside(Geometry.transfer(F(2000, 900, 900, 600), from: channel, to: laptop), laptop))
}

// Test 17: The grid families list every grid name once, in reading order.
@Test func testGrids() {
    #expect(Geometry.grids["sixths"] == [
        "top-left-sixth", "top-center-sixth", "top-right-sixth",
        "bottom-left-sixth", "bottom-center-sixth", "bottom-right-sixth",
    ])
    #expect(Geometry.grids["ninths"]?.count == 9)
    #expect(Geometry.grids["eighths"]?.count == 8)
    #expect(Geometry.grids["cornerThirds"]?.count == 4)
    for name in Geometry.grids.values.joined() {
        #expect(Geometry.position(name, channel) != nil, "\(name)")
    }
}

// Test 18: A custom size covers its share of the area, with and without a gap.
@Test func testCustomShare() {
    #expect(Geometry.custom(channel, CustomSpec(x: 0.25, w: 0.5)) == F(1088, 25, 1152, 1415))
    #expect(Geometry.custom(channel, CustomSpec()) == channel)
    #expect(Geometry.custom(channel, CustomSpec(x: 0.5, y: 0.5, w: 0.5, h: 0.5)) == Geometry.position("bottom-right", channel))
    #expect(Geometry.custom(channel, CustomSpec(w: 0.5), gap: 10) == Geometry.position("left-half", channel, gap: 10))
    #expect(Geometry.custom(channel, CustomSpec(x: 0.5, w: 0.5), gap: 10) == Geometry.position("right-half", channel, gap: 10))
    #expect(Geometry.custom(channel, CustomSpec(x: 1.0 / 3, w: 2.0 / 3)) == Geometry.position("last-two-thirds", channel))
    #expect(Geometry.custom(channel, CustomSpec(w: 2.0 / 3)) == Geometry.position("first-two-thirds", channel))
}

// Test 19: A custom pixel size is centered in its share and shrunk to fit.
@Test func testCustomPoints() {
    #expect(Geometry.custom(channel, CustomSpec(width: 1280, height: 720)) == F(1024, 373, 1280, 720))
    #expect(Geometry.custom(channel, CustomSpec(x: 0, w: 0.25, width: 1000)) == F(512, 25, 576, 1415))
    #expect(Geometry.custom(channel, CustomSpec(w: 0.5, height: 415)) == F(512, 525, 1152, 415))
    #expect(Geometry.custom(channel, CustomSpec(height: 5000)) == channel)
}

// Test 20: A share whose product lands just under a whole point by float error is not cut short.
@Test func testCustomFloat() {
    let square = F(0, 0, 100, 100)
    #expect(100 * 0.29 < 29, "the float case no longer applies")
    #expect(Geometry.custom(square, CustomSpec(w: 0.29)) == F(0, 0, 29, 100))
}

// Test 21: The top row takes its share of the height and the bottom row takes the rest.
@Test func testSlotRows() {
    #expect(Geometry.slot(screen, .left, .top, 10) == Geometry.slot(screen, .left, .top, 10, topPct: 50))
    #expect(Geometry.slot(screen, .left, .top, 10, topPct: 10) == F(0, 25, 512, 141))
    #expect(Geometry.slot(screen, .left, .bottom, 10, topPct: 10) == F(0, 166, 512, 1274))
    #expect(Geometry.slot(screen, .right, .top, 45, topPct: 90) == F(2816, 25, 2304, 1273))
    #expect(Geometry.slot(screen, .left, nil, 10, topPct: 10) == F(0, 25, 512, 1415))
    for pct in [10.0, 25, 33, 50, 67, 75, 90] {
        let top = Geometry.slot(screen, .left, .top, 10, topPct: pct)
        let bottom = Geometry.slot(screen, .left, .bottom, 10, topPct: pct)
        #expect(top.y + top.h == bottom.y, "\(pct) \(top) \(bottom)")
        #expect(top.h + bottom.h == screen.h, "\(pct) \(top) \(bottom)")
    }
}

// Test 22: A lifted pin covers its strip and the channel at full height and stops at the other
// strip, on a screen that does not start at zero.
@Test func testLift() {
    let offset = F(100, 25, 5120, 1415)
    #expect(Geometry.lift(offset, .left, 10, 45) == F(100, 25, 2816, 1415))
    #expect(Geometry.lift(offset, .right, 10, 45) == F(612, 25, 4608, 1415))
    let r = Geometry.regions(offset, 13.05, 45)
    #expect(Geometry.lift(offset, .right, 13.05, 45).x == r.left.x + r.left.w)
}
