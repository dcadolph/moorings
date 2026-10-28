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
    // Test 0: Left half.
    PositionCase(name: "left-half", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1152, 1415)),
    // Test 0: Right half.
    PositionCase(name: "right-half", area: channel, cur: nil, gap: 0, wantFrame: F(1664, 25, 1152, 1415)),
    // Test 0: Top half.
    PositionCase(name: "top-half", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 2304, 707)),
    // Test 0: Bottom half.
    PositionCase(name: "bottom-half", area: channel, cur: nil, gap: 0, wantFrame: F(512, 732, 2304, 708)),
    // Test 0: Center half.
    PositionCase(name: "center-half", area: channel, cur: nil, gap: 0, wantFrame: F(1088, 25, 1152, 1415)),
    // Test 1: Top left.
    PositionCase(name: "top-left", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1152, 707)),
    // Test 1: Bottom right.
    PositionCase(name: "bottom-right", area: channel, cur: nil, gap: 0, wantFrame: F(1664, 732, 1152, 708)),
    // Test 2: First third.
    PositionCase(name: "first-third", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 768, 1415)),
    // Test 2: First two.
    PositionCase(name: "first-two-thirds", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1536, 1415)),
    // Test 2: Last two.
    PositionCase(name: "last-two-thirds", area: channel, cur: nil, gap: 0, wantFrame: F(1280, 25, 1536, 1415)),
    // Test 2: Center two.
    PositionCase(name: "center-two-thirds", area: channel, cur: nil, gap: 0, wantFrame: F(896, 25, 1536, 1415)),
    // Test 3: Tall first third.
    PositionCase(name: "first-third", area: tall, cur: nil, gap: 0, wantFrame: F(0, 25, 1080, 631)),
    // Test 3: Tall last fourth.
    PositionCase(name: "last-fourth", area: tall, cur: nil, gap: 0, wantFrame: F(0, 1446, 1080, 474)),
    // Test 3: Halves stay.
    PositionCase(name: "left-half", area: tall, cur: nil, gap: 0, wantFrame: F(0, 25, 540, 1895)),
    // Test 4: Wide TL.
    PositionCase(name: "top-left-third", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1536, 707)),
    // Test 4: Wide BR.
    PositionCase(name: "bottom-right-third", area: channel, cur: nil, gap: 0, wantFrame: F(1280, 732, 1536, 708)),
    // Test 4: Tall TR.
    PositionCase(name: "top-right-third", area: tall, cur: nil, gap: 0, wantFrame: F(540, 25, 540, 1263)),
    // Test 4: Tall BL.
    PositionCase(name: "bottom-left-third", area: tall, cur: nil, gap: 0, wantFrame: F(0, 656, 540, 1264)),
    // Test 5: First three.
    PositionCase(name: "first-three-fourths", area: channel, cur: nil, gap: 0, wantFrame: F(512, 25, 1728, 1415)),
    // Test 5: Last three.
    PositionCase(name: "last-three-fourths", area: channel, cur: nil, gap: 0, wantFrame: F(1088, 25, 1728, 1415)),
    // Test 5: Center three.
    PositionCase(name: "center-three-fourths", area: channel, cur: nil, gap: 0, wantFrame: F(800, 25, 1728, 1415)),
    // Test 6: Ninth.
    PositionCase(name: "middle-center-ninth", area: channel, cur: nil, gap: 0, wantFrame: F(1280, 496, 768, 472)),
    // Test 6: Eighth.
    PositionCase(name: "top-center-right-eighth", area: channel, cur: nil, gap: 0, wantFrame: F(1664, 25, 576, 707)),
    // Test 7: Gap left.
    PositionCase(name: "left-half", area: channel, cur: nil, gap: 10, wantFrame: F(522, 35, 1137, 1395)),
    // Test 7: Gap right.
    PositionCase(name: "right-half", area: channel, cur: nil, gap: 10, wantFrame: F(1669, 35, 1137, 1395)),
    // Test 7: Gap maximize.
    PositionCase(name: "maximize", area: channel, cur: window, gap: 10, wantFrame: F(522, 35, 2284, 1395)),
    // Test 8: Maximize.
    PositionCase(name: "maximize", area: channel, cur: window, gap: 0, wantFrame: channel),
    // Test 8: Almost.
    PositionCase(name: "almost-maximize", area: channel, cur: window, gap: 0, wantFrame: F(627, 96, 2074, 1274)),
    // Test 8: Height.
    PositionCase(name: "maximize-height", area: channel, cur: window, gap: 0, wantFrame: F(600, 25, 1000, 1415)),
    // Test 8: Height gap.
    PositionCase(name: "maximize-height", area: channel, cur: window, gap: 10, wantFrame: F(600, 35, 1000, 1395)),
    // Test 9: Center.
    PositionCase(name: "center", area: channel, cur: window, gap: 0, wantFrame: F(1164, 333, 1000, 800)),
    // Test 9: Wide.
    PositionCase(name: "center", area: channel, cur: F(0, 0, 3000, 800), gap: 0, wantFrame: F(512, 333, 2304, 800)),
    // Test 9: Tall.
    PositionCase(name: "center", area: channel, cur: F(0, 0, 1000, 2000), gap: 0, wantFrame: F(1164, 25, 1000, 1415)),
    // Test 10: Prominent.
    PositionCase(name: "center-prominently", area: channel, cur: window, gap: 0, wantFrame: F(1164, 179, 1000, 800)),
    // Test 11: Move left.
    PositionCase(name: "move-left", area: channel, cur: window, gap: 0, wantFrame: F(512, 333, 1000, 800)),
    // Test 11: Move right.
    PositionCase(name: "move-right", area: channel, cur: window, gap: 0, wantFrame: F(1816, 333, 1000, 800)),
    // Test 11: Move up.
    PositionCase(name: "move-up", area: channel, cur: window, gap: 0, wantFrame: F(1164, 25, 1000, 800)),
    // Test 11: Move down.
    PositionCase(name: "move-down", area: channel, cur: window, gap: 0, wantFrame: F(1164, 640, 1000, 800)),
    // Test 11: Top left corner.
    PositionCase(name: "move-top-left", area: channel, cur: window, gap: 0, wantFrame: F(512, 25, 1000, 800)),
    // Test 11: Top right corner.
    PositionCase(name: "move-top-right", area: channel, cur: window, gap: 0, wantFrame: F(1816, 25, 1000, 800)),
    // Test 11: Bottom left corner.
    PositionCase(name: "move-bottom-left", area: channel, cur: window, gap: 0, wantFrame: F(512, 640, 1000, 800)),
    // Test 11: Bottom right corner, gap.
    PositionCase(name: "move-bottom-right", area: channel, cur: window, gap: 10, wantFrame: F(1806, 630, 1000, 800)),
    // Test 11: Corner, too wide.
    PositionCase(
        name: "move-top-right", area: channel, cur: F(0, 0, 3000, 800), gap: 0, wantFrame: F(512, 25, 2304, 800)),
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
    for name in Geometry.names() where name.hasSuffix("-\(suffix)") && !name.contains("-vertical-") {
        let f = try #require(Geometry.position(name, channel))
        #expect(inside(f, channel), "\(name) \(f)")
        total += f.w * f.h
        count += 1
    }
    #expect(count == wantCount)
    #expect(total == channel.w * channel.h)
}

// finerArea is a 1200 by 800 area for the vertical and finer grid families.
let finerArea = F(0, 0, 1200, 800)

// finerCases covers every vertical third, sixth, eighth, twelfth and sixteenth name at gap 0 and 10.
let finerCases: [PositionCase] = [
    // Test 19: first-vertical-sixth.
    PositionCase(name: "first-vertical-sixth", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 0, 200, 800)),
    // Test 19: second-vertical-sixth.
    PositionCase(name: "second-vertical-sixth", area: finerArea, cur: nil, gap: 0, wantFrame: F(200, 0, 200, 800)),
    // Test 19: third-vertical-sixth.
    PositionCase(name: "third-vertical-sixth", area: finerArea, cur: nil, gap: 0, wantFrame: F(400, 0, 200, 800)),
    // Test 19: fourth-vertical-sixth.
    PositionCase(name: "fourth-vertical-sixth", area: finerArea, cur: nil, gap: 0, wantFrame: F(600, 0, 200, 800)),
    // Test 19: fifth-vertical-sixth.
    PositionCase(name: "fifth-vertical-sixth", area: finerArea, cur: nil, gap: 0, wantFrame: F(800, 0, 200, 800)),
    // Test 19: last-vertical-sixth.
    PositionCase(name: "last-vertical-sixth", area: finerArea, cur: nil, gap: 0, wantFrame: F(1000, 0, 200, 800)),
    // Test 19: first-vertical-eighth.
    PositionCase(name: "first-vertical-eighth", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 0, 150, 800)),
    // Test 19: second-vertical-eighth.
    PositionCase(name: "second-vertical-eighth", area: finerArea, cur: nil, gap: 0, wantFrame: F(150, 0, 150, 800)),
    // Test 19: third-vertical-eighth.
    PositionCase(name: "third-vertical-eighth", area: finerArea, cur: nil, gap: 0, wantFrame: F(300, 0, 150, 800)),
    // Test 19: fourth-vertical-eighth.
    PositionCase(name: "fourth-vertical-eighth", area: finerArea, cur: nil, gap: 0, wantFrame: F(450, 0, 150, 800)),
    // Test 19: fifth-vertical-eighth.
    PositionCase(name: "fifth-vertical-eighth", area: finerArea, cur: nil, gap: 0, wantFrame: F(600, 0, 150, 800)),
    // Test 19: sixth-vertical-eighth.
    PositionCase(name: "sixth-vertical-eighth", area: finerArea, cur: nil, gap: 0, wantFrame: F(750, 0, 150, 800)),
    // Test 19: seventh-vertical-eighth.
    PositionCase(name: "seventh-vertical-eighth", area: finerArea, cur: nil, gap: 0, wantFrame: F(900, 0, 150, 800)),
    // Test 19: last-vertical-eighth.
    PositionCase(name: "last-vertical-eighth", area: finerArea, cur: nil, gap: 0, wantFrame: F(1050, 0, 150, 800)),
    // Test 19: top-vertical-third.
    PositionCase(name: "top-vertical-third", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 0, 1200, 266)),
    // Test 19: middle-vertical-third.
    PositionCase(name: "middle-vertical-third", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 266, 1200, 267)),
    // Test 19: bottom-vertical-third.
    PositionCase(name: "bottom-vertical-third", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 533, 1200, 267)),
    // Test 19: top-vertical-two-thirds.
    PositionCase(name: "top-vertical-two-thirds", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 0, 1200, 533)),
    // Test 19: bottom-vertical-two-thirds.
    PositionCase(
        name: "bottom-vertical-two-thirds", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 266, 1200, 534)),
    // Test 19: top-left-twelfth.
    PositionCase(name: "top-left-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 0, 300, 266)),
    // Test 19: top-center-left-twelfth.
    PositionCase(name: "top-center-left-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(300, 0, 300, 266)),
    // Test 19: top-center-right-twelfth.
    PositionCase(name: "top-center-right-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(600, 0, 300, 266)),
    // Test 19: top-right-twelfth.
    PositionCase(name: "top-right-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(900, 0, 300, 266)),
    // Test 19: middle-left-twelfth.
    PositionCase(name: "middle-left-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 266, 300, 267)),
    // Test 19: middle-center-left-twelfth.
    PositionCase(
        name: "middle-center-left-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(300, 266, 300, 267)),
    // Test 19: middle-center-right-twelfth.
    PositionCase(
        name: "middle-center-right-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(600, 266, 300, 267)),
    // Test 19: middle-right-twelfth.
    PositionCase(name: "middle-right-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(900, 266, 300, 267)),
    // Test 19: bottom-left-twelfth.
    PositionCase(name: "bottom-left-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 533, 300, 267)),
    // Test 19: bottom-center-left-twelfth.
    PositionCase(
        name: "bottom-center-left-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(300, 533, 300, 267)),
    // Test 19: bottom-center-right-twelfth.
    PositionCase(
        name: "bottom-center-right-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(600, 533, 300, 267)),
    // Test 19: bottom-right-twelfth.
    PositionCase(name: "bottom-right-twelfth", area: finerArea, cur: nil, gap: 0, wantFrame: F(900, 533, 300, 267)),
    // Test 19: top-left-sixteenth.
    PositionCase(name: "top-left-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 0, 300, 200)),
    // Test 19: top-center-left-sixteenth.
    PositionCase(name: "top-center-left-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(300, 0, 300, 200)),
    // Test 19: top-center-right-sixteenth.
    PositionCase(name: "top-center-right-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(600, 0, 300, 200)),
    // Test 19: top-right-sixteenth.
    PositionCase(name: "top-right-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(900, 0, 300, 200)),
    // Test 19: upper-middle-left-sixteenth.
    PositionCase(
        name: "upper-middle-left-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 200, 300, 200)),
    // Test 19: upper-middle-center-left-sixteenth.
    PositionCase(
        name: "upper-middle-center-left-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(300, 200, 300, 200)),
    // Test 19: upper-middle-center-right-sixteenth.
    PositionCase(
        name: "upper-middle-center-right-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(600, 200, 300, 200)
    ),
    // Test 19: upper-middle-right-sixteenth.
    PositionCase(
        name: "upper-middle-right-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(900, 200, 300, 200)),
    // Test 19: lower-middle-left-sixteenth.
    PositionCase(
        name: "lower-middle-left-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 400, 300, 200)),
    // Test 19: lower-middle-center-left-sixteenth.
    PositionCase(
        name: "lower-middle-center-left-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(300, 400, 300, 200)),
    // Test 19: lower-middle-center-right-sixteenth.
    PositionCase(
        name: "lower-middle-center-right-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(600, 400, 300, 200)
    ),
    // Test 19: lower-middle-right-sixteenth.
    PositionCase(
        name: "lower-middle-right-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(900, 400, 300, 200)),
    // Test 19: bottom-left-sixteenth.
    PositionCase(name: "bottom-left-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(0, 600, 300, 200)),
    // Test 19: bottom-center-left-sixteenth.
    PositionCase(
        name: "bottom-center-left-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(300, 600, 300, 200)),
    // Test 19: bottom-center-right-sixteenth.
    PositionCase(
        name: "bottom-center-right-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(600, 600, 300, 200)),
    // Test 19: bottom-right-sixteenth.
    PositionCase(name: "bottom-right-sixteenth", area: finerArea, cur: nil, gap: 0, wantFrame: F(900, 600, 300, 200)),
    // Test 19: first-vertical-sixth.
    PositionCase(name: "first-vertical-sixth", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 10, 185, 780)),
    // Test 19: second-vertical-sixth.
    PositionCase(name: "second-vertical-sixth", area: finerArea, cur: nil, gap: 10, wantFrame: F(205, 10, 190, 780)),
    // Test 19: third-vertical-sixth.
    PositionCase(name: "third-vertical-sixth", area: finerArea, cur: nil, gap: 10, wantFrame: F(405, 10, 190, 780)),
    // Test 19: fourth-vertical-sixth.
    PositionCase(name: "fourth-vertical-sixth", area: finerArea, cur: nil, gap: 10, wantFrame: F(605, 10, 190, 780)),
    // Test 19: fifth-vertical-sixth.
    PositionCase(name: "fifth-vertical-sixth", area: finerArea, cur: nil, gap: 10, wantFrame: F(805, 10, 190, 780)),
    // Test 19: last-vertical-sixth.
    PositionCase(name: "last-vertical-sixth", area: finerArea, cur: nil, gap: 10, wantFrame: F(1005, 10, 185, 780)),
    // Test 19: first-vertical-eighth.
    PositionCase(name: "first-vertical-eighth", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 10, 135, 780)),
    // Test 19: second-vertical-eighth.
    PositionCase(name: "second-vertical-eighth", area: finerArea, cur: nil, gap: 10, wantFrame: F(155, 10, 140, 780)),
    // Test 19: third-vertical-eighth.
    PositionCase(name: "third-vertical-eighth", area: finerArea, cur: nil, gap: 10, wantFrame: F(305, 10, 140, 780)),
    // Test 19: fourth-vertical-eighth.
    PositionCase(name: "fourth-vertical-eighth", area: finerArea, cur: nil, gap: 10, wantFrame: F(455, 10, 140, 780)),
    // Test 19: fifth-vertical-eighth.
    PositionCase(name: "fifth-vertical-eighth", area: finerArea, cur: nil, gap: 10, wantFrame: F(605, 10, 140, 780)),
    // Test 19: sixth-vertical-eighth.
    PositionCase(name: "sixth-vertical-eighth", area: finerArea, cur: nil, gap: 10, wantFrame: F(755, 10, 140, 780)),
    // Test 19: seventh-vertical-eighth.
    PositionCase(name: "seventh-vertical-eighth", area: finerArea, cur: nil, gap: 10, wantFrame: F(905, 10, 140, 780)),
    // Test 19: last-vertical-eighth.
    PositionCase(name: "last-vertical-eighth", area: finerArea, cur: nil, gap: 10, wantFrame: F(1055, 10, 135, 780)),
    // Test 19: top-vertical-third.
    PositionCase(name: "top-vertical-third", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 10, 1180, 251)),
    // Test 19: middle-vertical-third.
    PositionCase(name: "middle-vertical-third", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 271, 1180, 257)),
    // Test 19: bottom-vertical-third.
    PositionCase(name: "bottom-vertical-third", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 538, 1180, 252)),
    // Test 19: top-vertical-two-thirds.
    PositionCase(name: "top-vertical-two-thirds", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 10, 1180, 518)),
    // Test 19: bottom-vertical-two-thirds.
    PositionCase(
        name: "bottom-vertical-two-thirds", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 271, 1180, 519)),
    // Test 19: top-left-twelfth.
    PositionCase(name: "top-left-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 10, 285, 251)),
    // Test 19: top-center-left-twelfth.
    PositionCase(name: "top-center-left-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(305, 10, 290, 251)),
    // Test 19: top-center-right-twelfth.
    PositionCase(name: "top-center-right-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(605, 10, 290, 251)),
    // Test 19: top-right-twelfth.
    PositionCase(name: "top-right-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(905, 10, 285, 251)),
    // Test 19: middle-left-twelfth.
    PositionCase(name: "middle-left-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 271, 285, 257)),
    // Test 19: middle-center-left-twelfth.
    PositionCase(
        name: "middle-center-left-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(305, 271, 290, 257)),
    // Test 19: middle-center-right-twelfth.
    PositionCase(
        name: "middle-center-right-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(605, 271, 290, 257)),
    // Test 19: middle-right-twelfth.
    PositionCase(name: "middle-right-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(905, 271, 285, 257)),
    // Test 19: bottom-left-twelfth.
    PositionCase(name: "bottom-left-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 538, 285, 252)),
    // Test 19: bottom-center-left-twelfth.
    PositionCase(
        name: "bottom-center-left-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(305, 538, 290, 252)),
    // Test 19: bottom-center-right-twelfth.
    PositionCase(
        name: "bottom-center-right-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(605, 538, 290, 252)),
    // Test 19: bottom-right-twelfth.
    PositionCase(name: "bottom-right-twelfth", area: finerArea, cur: nil, gap: 10, wantFrame: F(905, 538, 285, 252)),
    // Test 19: top-left-sixteenth.
    PositionCase(name: "top-left-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 10, 285, 185)),
    // Test 19: top-center-left-sixteenth.
    PositionCase(
        name: "top-center-left-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(305, 10, 290, 185)),
    // Test 19: top-center-right-sixteenth.
    PositionCase(
        name: "top-center-right-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(605, 10, 290, 185)),
    // Test 19: top-right-sixteenth.
    PositionCase(name: "top-right-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(905, 10, 285, 185)),
    // Test 19: upper-middle-left-sixteenth.
    PositionCase(
        name: "upper-middle-left-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 205, 285, 190)),
    // Test 19: upper-middle-center-left-sixteenth.
    PositionCase(
        name: "upper-middle-center-left-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(305, 205, 290, 190)
    ),
    // Test 19: upper-middle-center-right-sixteenth.
    PositionCase(
        name: "upper-middle-center-right-sixteenth", area: finerArea, cur: nil, gap: 10,
        wantFrame: F(605, 205, 290, 190)),
    // Test 19: upper-middle-right-sixteenth.
    PositionCase(
        name: "upper-middle-right-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(905, 205, 285, 190)),
    // Test 19: lower-middle-left-sixteenth.
    PositionCase(
        name: "lower-middle-left-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 405, 285, 190)),
    // Test 19: lower-middle-center-left-sixteenth.
    PositionCase(
        name: "lower-middle-center-left-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(305, 405, 290, 190)
    ),
    // Test 19: lower-middle-center-right-sixteenth.
    PositionCase(
        name: "lower-middle-center-right-sixteenth", area: finerArea, cur: nil, gap: 10,
        wantFrame: F(605, 405, 290, 190)),
    // Test 19: lower-middle-right-sixteenth.
    PositionCase(
        name: "lower-middle-right-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(905, 405, 285, 190)),
    // Test 19: bottom-left-sixteenth.
    PositionCase(name: "bottom-left-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(10, 605, 285, 185)),
    // Test 19: bottom-center-left-sixteenth.
    PositionCase(
        name: "bottom-center-left-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(305, 605, 290, 185)),
    // Test 19: bottom-center-right-sixteenth.
    PositionCase(
        name: "bottom-center-right-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(605, 605, 290, 185)),
    // Test 19: bottom-right-sixteenth.
    PositionCase(name: "bottom-right-sixteenth", area: finerArea, cur: nil, gap: 10, wantFrame: F(905, 605, 285, 185)),
]

// testFinerGrids checks each vertical and finer grid name against its frame.
@Test(arguments: finerCases)
func testFinerGrids(test: PositionCase) {
    #expect(Geometry.position(test.name, test.area, test.cur, gap: test.gap) == test.wantFrame)
}

// Test 20: The finer families cover the area with no overlap.
@Test(arguments: [("verticalSixths", 6), ("verticalEighths", 8), ("twelfths", 12), ("sixteenths", 16)])
func testFinerCover(family: String, wantCount: Int) throws {
    let names = try #require(Geometry.grids[family])
    var total = 0.0
    for name in names {
        let f = try #require(Geometry.position(name, finerArea))
        #expect(inside(f, finerArea), "\(name) \(f)")
        total += f.w * f.h
    }
    #expect(names.count == wantCount)
    #expect(total == finerArea.w * finerArea.h)
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
    #expect(Geometry.names().count == 121)
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
    // Test 15: Larger.
    ResizeCase(cur: window, d: 30, wantFrame: F(570, 70, 1060, 860)),
    // Test 15: Smaller.
    ResizeCase(cur: window, d: -30, wantFrame: F(630, 130, 940, 740)),
    // Test 15: Larger curtain.
    ResizeCase(cur: F(512, 25, 1152, 1415), d: 30, wantFrame: F(512, 25, 1182, 1415)),
    // Test 15: Smaller curtain.
    ResizeCase(cur: F(512, 25, 1152, 1415), d: -30, wantFrame: F(512, 55, 1122, 1355)),
    // Test 15: Smaller full.
    ResizeCase(cur: channel, d: -30, wantFrame: F(542, 55, 2244, 1355)),
    // Test 15: Larger full.
    ResizeCase(cur: channel, d: 30, wantFrame: channel),
    // Test 15: Stops at edge.
    ResizeCase(cur: F(530, 100, 1000, 800), d: 30, wantFrame: F(512, 70, 1048, 860)),
    // Test 15: Smaller floor.
    ResizeCase(cur: F(600, 100, 600, 800), d: -30, wantFrame: F(600, 130, 600, 740)),
    // Test 15: Clamped first.
    ResizeCase(cur: F(0, 0, 3000, 500), d: 30, wantFrame: F(512, 25, 2304, 530)),
]

// testResize checks larger and smaller against the Lua frames.
@Test(arguments: resizeCases)
func testResize(test: ResizeCase) {
    #expect(Geometry.resize(channel, test.cur, test.d) == test.wantFrame)
}

// AxisCase is one expectation of a one-axis size action.
struct AxisCase: Sendable, CustomTestStringConvertible {
    // Name is the action name.
    let name: String
    // Cur is the window's current frame.
    let cur: Frame
    // WantFrame is the expected frame.
    let wantFrame: Frame

    // testDescription labels the case in test output.
    var testDescription: String { "\(name) \(cur)" }
}

let broad = F(600, 100, 1400, 800)

// axisCases covers larger, smaller, double and halve on one axis, including the clamp at an edge.
let axisCases: [AxisCase] = [
    // Test 23: Larger width.
    AxisCase(name: "larger-width", cur: window, wantFrame: F(570, 100, 1060, 800)),
    // Test 23: Larger width clamp.
    AxisCase(name: "larger-width", cur: F(520, 100, 1000, 800), wantFrame: F(512, 100, 1038, 800)),
    // Test 23: Larger width curtain.
    AxisCase(name: "larger-width", cur: F(512, 100, 1000, 800), wantFrame: F(512, 100, 1030, 800)),
    // Test 23: Smaller width.
    AxisCase(name: "smaller-width", cur: window, wantFrame: F(630, 100, 940, 800)),
    // Test 23: Smaller width curtain.
    AxisCase(name: "smaller-width", cur: F(512, 100, 1000, 800), wantFrame: F(512, 100, 970, 800)),
    // Test 23: Smaller width floor.
    AxisCase(name: "smaller-width", cur: F(600, 100, 600, 800), wantFrame: F(600, 100, 600, 800)),
    // Test 23: Larger height.
    AxisCase(name: "larger-height", cur: window, wantFrame: F(600, 70, 1000, 860)),
    // Test 23: Larger height clamp.
    AxisCase(name: "larger-height", cur: F(600, 35, 1000, 800), wantFrame: F(600, 25, 1000, 840)),
    // Test 23: Smaller height.
    AxisCase(name: "smaller-height", cur: window, wantFrame: F(600, 130, 1000, 740)),
    // Test 23: Smaller height full.
    AxisCase(name: "smaller-height", cur: F(600, 25, 1000, 1415), wantFrame: F(600, 55, 1000, 1355)),
    // Test 23: Double width right.
    AxisCase(name: "double-width-right", cur: window, wantFrame: F(600, 100, 2000, 800)),
    // Test 23: Double width right clamp.
    AxisCase(name: "double-width-right", cur: F(2200, 100, 500, 800), wantFrame: F(2200, 100, 616, 800)),
    // Test 23: Double width left.
    AxisCase(name: "double-width-left", cur: F(1500, 100, 400, 800), wantFrame: F(1100, 100, 800, 800)),
    // Test 23: Double width left clamp.
    AxisCase(name: "double-width-left", cur: window, wantFrame: F(512, 100, 1088, 800)),
    // Test 23: Double height up.
    AxisCase(name: "double-height-up", cur: F(600, 900, 1000, 300), wantFrame: F(600, 600, 1000, 600)),
    // Test 23: Double height up clamp.
    AxisCase(name: "double-height-up", cur: window, wantFrame: F(600, 25, 1000, 875)),
    // Test 23: Double height down.
    AxisCase(name: "double-height-down", cur: F(600, 100, 1000, 300), wantFrame: F(600, 100, 1000, 600)),
    // Test 23: Double height down clamp.
    AxisCase(name: "double-height-down", cur: window, wantFrame: F(600, 100, 1000, 1340)),
    // Test 23: Halve width left.
    AxisCase(name: "halve-width-left", cur: broad, wantFrame: F(600, 100, 700, 800)),
    // Test 23: Halve width right.
    AxisCase(name: "halve-width-right", cur: broad, wantFrame: F(1300, 100, 700, 800)),
    // Test 23: Halve height up.
    AxisCase(name: "halve-height-up", cur: broad, wantFrame: F(600, 100, 1400, 400)),
    // Test 23: Halve height down.
    AxisCase(name: "halve-height-down", cur: broad, wantFrame: F(600, 500, 1400, 400)),
    // Test 23: Halve width too small.
    AxisCase(name: "halve-width-left", cur: window, wantFrame: window),
    // Test 23: Halve height too small.
    AxisCase(name: "halve-height-down", cur: F(600, 100, 1000, 600), wantFrame: F(600, 100, 1000, 600)),
]

// testAxisActions checks the one-axis size actions.
@Test(arguments: axisCases)
func testAxisActions(test: AxisCase) {
    #expect(Geometry.position(test.name, channel, test.cur) == test.wantFrame)
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
    #expect(
        Geometry.grids["sixths"] == [
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
    #expect(
        Geometry.custom(channel, CustomSpec(x: 0.5, y: 0.5, w: 0.5, h: 0.5))
            == Geometry.position("bottom-right", channel))
    #expect(Geometry.custom(channel, CustomSpec(w: 0.5), gap: 10) == Geometry.position("left-half", channel, gap: 10))
    #expect(
        Geometry.custom(channel, CustomSpec(x: 0.5, w: 0.5), gap: 10)
            == Geometry.position("right-half", channel, gap: 10))
    #expect(
        Geometry.custom(channel, CustomSpec(x: 1.0 / 3, w: 2.0 / 3)) == Geometry.position("last-two-thirds", channel))
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

// Test 23: Each side and center-section alias equals its half and stays out of the names.
@Test func testSideAliases() throws {
    let pairs = [
        ("left-side", "left-half"), ("right-side", "right-half"), ("bottom-side", "bottom-half"),
        ("top-side", "top-half"), ("center-section", "center-half"),
    ]
    for (alias, half) in pairs {
        let want = try #require(Geometry.position(half, channel, window, gap: 10))
        #expect(Geometry.position(alias, channel, window, gap: 10) == want, "\(alias)")
        #expect(Geometry.cycle(alias, 1, channel, window) == Geometry.cycle(half, 1, channel, window))
        #expect(!Geometry.names().contains(alias))
    }
}

// Test 24: A points-sized spec centers in the area and shrinks to fit.
@Test func testPointsSpec() {
    let spec = CustomSpec(width: 1680, height: 1050)
    #expect(Geometry.custom(channel, spec) == F(824, 208, 1680, 1050))
    #expect(Geometry.custom(F(0, 0, 1000, 800), spec) == F(0, 0, 1000, 800))
}

// fillArea is the area the fill tests grow a window within.
let fillArea = F(0, 0, 1000, 800)

// Test: Fill left with nothing beside the window reaches the area's left edge and keeps the rest.
@Test func testFillLeftOpen() {
    let cur = F(300, 100, 200, 300)
    #expect(Geometry.fill(cur, .left, area: fillArea, others: []) == F(0, 100, 500, 300))
}

// Test: Fill left stops at the right edge of a window on the left that overlaps vertically.
@Test func testFillLeftStops() {
    let cur = F(300, 100, 200, 300)
    let others = [F(50, 50, 100, 200), F(0, 0, 60, 800)]
    #expect(Geometry.fill(cur, .left, area: fillArea, others: others) == F(150, 100, 350, 300))
}

// Test: Fill left ignores windows that do not overlap vertically or only touch top to bottom.
@Test func testFillLeftIgnores() {
    let cur = F(300, 100, 200, 300)
    let apart = F(100, 500, 150, 100)
    let touching = F(100, 400, 150, 100)
    #expect(Geometry.fill(cur, .left, area: fillArea, others: [apart, touching]) == F(0, 100, 500, 300))
}

// Test: Fill left leaves the gap, and a window already touching its stop is returned unchanged.
@Test func testFillLeftGapAndTouching() {
    let cur = F(300, 100, 200, 300)
    #expect(
        Geometry.fill(cur, .left, area: fillArea, others: [F(50, 50, 100, 200)], gap: 10)
            == F(160, 100, 340, 300))
    #expect(Geometry.fill(cur, .left, area: fillArea, others: [F(100, 50, 200, 200)]) == cur)
    #expect(Geometry.fill(F(0, 100, 200, 300), .left, area: fillArea, others: []) == F(0, 100, 200, 300))
    #expect(Geometry.fill(F(5, 100, 200, 300), .left, area: fillArea, others: [], gap: 10) == F(5, 100, 200, 300))
}

// Test: Fill right with nothing beside the window reaches the area's right edge and keeps the rest.
@Test func testFillRightOpen() {
    let cur = F(300, 100, 200, 300)
    #expect(Geometry.fill(cur, .right, area: fillArea, others: []) == F(300, 100, 700, 300))
}

// Test: Fill right stops at a window on the right, ignores non-overlapping ones, and leaves the gap.
@Test func testFillRightStops() {
    let cur = F(300, 100, 200, 300)
    let others = [F(700, 50, 100, 200), F(600, 500, 100, 100), F(600, 400, 100, 100)]
    #expect(Geometry.fill(cur, .right, area: fillArea, others: others) == F(300, 100, 400, 300))
    #expect(Geometry.fill(cur, .right, area: fillArea, others: others, gap: 10) == F(300, 100, 390, 300))
}

// Test: Fill right already touching returns cur unchanged and never moves the left edge.
@Test func testFillRightTouching() {
    let cur = F(300, 100, 200, 300)
    #expect(Geometry.fill(cur, .right, area: fillArea, others: [F(500, 0, 100, 800)]) == cur)
    let grown = Geometry.fill(cur, .right, area: fillArea, others: [])
    #expect(grown.x == cur.x && grown.y == cur.y && grown.h == cur.h)
}
