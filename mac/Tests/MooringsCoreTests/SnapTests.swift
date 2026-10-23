import Testing

@testable import MooringsCore

// snapScreen is a 1920 by 1080 display at the origin.
let snapScreen = F(0, 0, 1920, 1080)

// snapSide is a display to the right of an ultrawide.
let snapSide = F(5120, 0, 1512, 982)

// snapWide is a 5120 by 1440 ultrawide, and channel is its default channel.
let snapWide = F(0, 0, 5120, 1440)

// snapZone returns the zone at x, y.
func snapZone(_ f: Frame, _ ch: Frame?, _ x: Double, _ y: Double, _ prev: String? = nil) -> String? {
    Snap.zone(SnapPoint(x, y), f, ch, prev)
}

// Lua case 0: Left and right edges give halves, near corners give quarters, and near-corner
// stretches give top and bottom halves.
@Test func testSnapEdges() {
    #expect(snapZone(snapScreen, nil, 0, 540) == "left-half")
    #expect(snapZone(snapScreen, nil, 4, 540) == "left-half")
    #expect(snapZone(snapScreen, nil, 5, 540) == nil)
    #expect(snapZone(snapScreen, nil, 1919, 540) == "right-half")
    #expect(snapZone(snapScreen, nil, 1915, 540) == "right-half")
    #expect(snapZone(snapScreen, nil, 1914, 540) == nil)
    #expect(snapZone(snapScreen, nil, 0, 19) == "top-left")
    #expect(snapZone(snapScreen, nil, 0, 20) == "top-half")
    #expect(snapZone(snapScreen, nil, 0, 145) == "left-half")
    #expect(snapZone(snapScreen, nil, 0, 1060) == "bottom-left")
    #expect(snapZone(snapScreen, nil, 0, 1000) == "bottom-half")
    #expect(snapZone(snapScreen, nil, 1919, 5) == "top-right")
    #expect(snapZone(snapScreen, nil, 1919, 1075) == "bottom-right")
}

// Lua case 1: The top edge maximizes, with corners and short stretches at its ends.
@Test func testSnapTop() {
    #expect(snapZone(snapScreen, nil, 960, 0) == "maximize")
    #expect(snapZone(snapScreen, nil, 960, 4) == "maximize")
    #expect(snapZone(snapScreen, nil, 960, 5) == nil)
    #expect(snapZone(snapScreen, nil, 19, 0) == "top-left")
    #expect(snapZone(snapScreen, nil, 1900, 0) == "top-right")
    #expect(snapZone(snapScreen, nil, 100, 0) == "top-half")
    #expect(snapZone(snapScreen, nil, 1800, 0) == "top-half")
}

// Lua case 2: The bottom edge gives thirds, and the center turns to two thirds coming from a side.
@Test func testSnapBottom() {
    #expect(snapZone(snapScreen, nil, 400, 1079) == "first-third")
    #expect(snapZone(snapScreen, nil, 960, 1079) == "center-third")
    #expect(snapZone(snapScreen, nil, 1500, 1079) == "last-third")
    #expect(snapZone(snapScreen, nil, 960, 1079, "first-third") == "first-two-thirds")
    #expect(snapZone(snapScreen, nil, 960, 1079, "first-two-thirds") == "first-two-thirds")
    #expect(snapZone(snapScreen, nil, 960, 1079, "last-third") == "last-two-thirds")
    #expect(snapZone(snapScreen, nil, 960, 1079, "last-two-thirds") == "last-two-thirds")
    #expect(snapZone(snapScreen, nil, 960, 1079, "maximize") == "center-third")
    #expect(snapZone(snapScreen, nil, 10, 1079) == "bottom-left")
    #expect(snapZone(snapScreen, nil, 1800, 1079) == "bottom-half")
    #expect(snapZone(snapScreen, nil, 960, 1074) == nil)
    #expect(snapZone(snapScreen, nil, 960, 540) == nil)
}

// Lua case 3: A display away from the origin measures from its own edges.
@Test func testSnapOffsetDisplay() {
    #expect(snapZone(snapSide, nil, 5120, 400) == "left-half")
    #expect(snapZone(snapSide, nil, 6631, 400) == "right-half")
    #expect(snapZone(snapSide, nil, 5900, 0) == "maximize")
    #expect(snapZone(snapSide, nil, 5200, 400) == nil)
    #expect(snapZone(snapSide, nil, 5300, 981) == "first-third")
    #expect(snapZone(snapSide, nil, 6400, 981) == "last-third")
}

// Lua case 4: On the ultrawide the strips stand in for the edges and the channel keeps top and
// bottom.
@Test func testSnapUltrawide() {
    #expect(snapZone(snapWide, channel, 200, 700) == "left-half")
    #expect(snapZone(snapWide, channel, 511, 700) == "left-half")
    #expect(snapZone(snapWide, channel, 512, 700) == nil)
    #expect(snapZone(snapWide, channel, 200, 50) == "top-left")
    #expect(snapZone(snapWide, channel, 200, 1400) == "bottom-left")
    #expect(snapZone(snapWide, channel, 4000, 700) == "right-half")
    #expect(snapZone(snapWide, channel, 2816, 700) == "right-half")
    #expect(snapZone(snapWide, channel, 2815, 700) == nil)
    #expect(snapZone(snapWide, channel, 4000, 30) == "top-right")
    #expect(snapZone(snapWide, channel, 5119, 1439) == "bottom-right")
    #expect(snapZone(snapWide, channel, 1500, 2) == "maximize")
    #expect(snapZone(snapWide, channel, 1000, 1439) == "first-third")
    #expect(snapZone(snapWide, channel, 1500, 1439) == "center-third")
    #expect(snapZone(snapWide, channel, 2500, 1439) == "last-third")
    #expect(snapZone(snapWide, channel, 1500, 1439, "last-third") == "last-two-thirds")
    #expect(snapZone(snapWide, channel, 1500, 700) == nil)
}

// Lua case 5: Park finds the strip half under the cursor and nothing over the channel.
@Test func testSnapPark() {
    #expect(Snap.park(SnapPoint(100, 100), snapWide, channel) == "left-top")
    #expect(Snap.park(SnapPoint(511, 720), snapWide, channel) == "left-bottom")
    #expect(Snap.park(SnapPoint(2816, 719), snapWide, channel) == "right-top")
    #expect(Snap.park(SnapPoint(5119, 1439), snapWide, channel) == "right-bottom")
    #expect(Snap.park(SnapPoint(512, 100), snapWide, channel) == nil)
    #expect(Snap.park(SnapPoint(2815, 100), snapWide, channel) == nil)
}

// Lua case 6: With a side empty the channel reaches that edge, and the last few points of the
// display stand in for the missing strip, for snapping and parking.
@Test func testSnapEmptySide() {
    let open = F(0, 25, 2816, 1415)
    #expect(snapZone(snapWide, open, 2, 700) == "left-half")
    #expect(snapZone(snapWide, open, 2, 10) == "top-left")
    #expect(snapZone(snapWide, open, 5, 700) == nil)
    #expect(snapZone(snapWide, open, 3000, 700) == "right-half")
    #expect(Snap.park(SnapPoint(4, 100), snapWide, open) == "left-top")
    #expect(Snap.park(SnapPoint(5, 100), snapWide, open) == nil)
    let both = F(0, 25, 5120, 1415)
    #expect(snapZone(snapWide, both, 5115, 700) == "right-half")
    #expect(snapZone(snapWide, both, 5114, 700) == nil)
}

// Swift only: Option over a strip parks a parkable window's app, and pinned or cast-off windows
// get no zone.
@Test func testSnapDrop() {
    let strip = SnapPoint(200, 700)
    #expect(Snap.drop(strip, snapWide, channel, option: true, parkable: true) == .park("left-top"))
    #expect(Snap.drop(strip, snapWide, channel, option: true) == nil)
    #expect(Snap.drop(SnapPoint(1500, 700), snapWide, channel, option: true, parkable: true) == nil)
    #expect(Snap.drop(strip, snapWide, channel) == .zone("left-half"))
    #expect(Snap.drop(strip, snapWide, channel, pinned: true) == nil)
    #expect(Snap.drop(strip, snapWide, channel, castOff: true) == nil)
    #expect(Snap.drop(SnapPoint(0, 540), snapScreen, option: true, parkable: true) == .zone("left-half"))
}
