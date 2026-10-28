import Foundation
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

// Swift only: a custom map changes what an area resolves to, and an ignored area resolves to nothing.
@Test func testSnapCustomMapAndIgnoredArea() {
    var m = SnapChoices()
    m.landscapeSnapAreas["top"] = "top-half"
    #expect(Snap.zone(SnapPoint(960, 0), snapScreen, nil, nil, snapping: m) == "top-half")
    #expect(Snap.zone(SnapPoint(960, 0), snapScreen) == "maximize")
    m.ignoredSnapAreas = ["left"]
    #expect(Snap.zone(SnapPoint(0, 540), snapScreen, nil, nil, snapping: m) == nil)
    #expect(Snap.zone(SnapPoint(0, 0), snapScreen, nil, nil, snapping: m) == "top-left")
}

// Swift only: snap modifiers gate the zone until every named key is held.
@Test func testSnapModifiersGate() {
    var m = SnapChoices()
    m.snapModifiers = ["shift"]
    #expect(Snap.zone(SnapPoint(0, 540), snapScreen, nil, nil, snapping: m) == nil)
    #expect(Snap.zone(SnapPoint(0, 540), snapScreen, nil, nil, snapping: m, held: ["shift"]) == "left-half")
}

// Swift only: edge margins, the snap-before distance and the corner size move where areas start.
@Test func testSnapMarginsAndSizes() {
    var m = SnapChoices()
    #expect(Snap.zone(SnapPoint(8, 540), snapScreen, nil, nil, snapping: m) == nil)
    m.edgeMarginLeft = 10
    #expect(Snap.zone(SnapPoint(8, 540), snapScreen, nil, nil, snapping: m) == "left-half")
    m = SnapChoices()
    m.snapBeforeReachingEdges = 20
    #expect(Snap.zone(SnapPoint(20, 540), snapScreen, nil, nil, snapping: m) == "left-half")
    m = SnapChoices()
    #expect(Snap.zone(SnapPoint(0, 100), snapScreen, nil, nil, snapping: m) == "top-half")
    m.cornerSize = 150
    #expect(Snap.zone(SnapPoint(0, 100), snapScreen, nil, nil, snapping: m) == "top-left")
}

// Swift only: the default footprint style keeps the palette's look, a color override and alpha change it, and a
// bad color falls back to the accent.
@Test func testFootprintStyleTints() {
    let p = Palette.harbor
    var s = FootprintStyle()
    #expect(s.tints(p).fill == p.footprintFill)
    #expect(s.tints(p).stroke == p.footprintStroke)
    s.color = "#ff0000"
    s.alpha = 0.5
    #expect(s.tints(p).fill == Tint(color: RGB(red: 1, green: 0, blue: 0), alpha: 0.5))
    #expect(s.tints(p).stroke == Tint(color: RGB(red: 1, green: 0, blue: 0), alpha: 0.70))
    s.color = "red"
    s.alpha = 4
    #expect(s.tints(p).fill == Tint(color: p.accent, alpha: 1))
}

// Swift only: the footprint fades only when fade is on, scaled by the animation speed.
@Test func testFootprintStyleFadeTime() {
    var s = FootprintStyle()
    #expect(s.fadeTime == 0)
    s.fade = true
    #expect(s.fadeTime == FootprintStyle.fadeSeconds)
    s.animationSpeed = 2
    #expect(s.fadeTime == FootprintStyle.fadeSeconds * 2)
}

// Swift only: a custom area off the ultrawide takes a drop before the edges, the first match wins, an
// empty action turns an area off, held keys still apply, and the ultrawide ignores custom areas.
@Test func testSnapCustomAreas() {
    var m = SnapChoices()
    m.customAreas = [CustomSnapArea(x: 0.4, y: 0.4, w: 0.2, h: 0.2, action: "center-third"),
                     CustomSnapArea(x: 0.4, y: 0.4, w: 0.6, h: 0.6, action: "bottom-right"),
                     CustomSnapArea(x: 0, y: 0, w: 0.1, h: 1, action: "")]
    #expect(Snap.zone(SnapPoint(960, 540), snapScreen, nil, nil, snapping: m) == "center-third")
    #expect(Snap.zone(SnapPoint(1500, 800), snapScreen, nil, nil, snapping: m) == "bottom-right")
    #expect(Snap.zone(SnapPoint(1919, 500), snapScreen, nil, nil, snapping: m) == "bottom-right")
    #expect(Snap.zone(SnapPoint(0, 500), snapScreen, nil, nil, snapping: m) == "left-half")
    #expect(Snap.zone(SnapPoint(300, 300), snapScreen, nil, nil, snapping: m) == nil)
    #expect(Snap.zone(SnapPoint(5120 + 756, 491), snapSide, nil, nil, snapping: m) == "center-third")
    let ch = F(512, 25, 4096, 1415)
    #expect(Snap.zone(SnapPoint(2560, 720), snapWide, ch, nil, snapping: m) == nil)
    m.snapModifiers = ["shift"]
    #expect(Snap.zone(SnapPoint(960, 540), snapScreen, nil, nil, snapping: m) == nil)
    #expect(Snap.zone(SnapPoint(960, 540), snapScreen, nil, nil, snapping: m, held: ["shift"]) == "center-third")
}

// Swift only: snap choices saved before custom areas and the panel load with neither, a bad area field
// reads 0, and both round trip.
@Test func testSnapChoicesCustomDecode() throws {
    let old = try JSONDecoder().decode(SnapChoices.self, from: Data(#"{"cornerSize":30}"#.utf8))
    #expect(old.customAreas.isEmpty && !old.snapPanel && old.panelActions == SnapPanel.defaultActions)
    let bad = try JSONDecoder().decode(CustomSnapArea.self, from: Data(#"{"x":"wide","w":0.5,"action":"maximize"}"#.utf8))
    #expect(bad == CustomSnapArea(x: 0, y: 0, w: 0.5, h: 0, action: "maximize"))
    var m = SnapChoices()
    m.customAreas = [CustomSnapArea(x: 0.1, y: 0.2, w: 0.3, h: 0.4, action: "maximize")]
    m.snapPanel = true
    m.panelActions = ["left-half"]
    #expect(try JSONDecoder().decode(SnapChoices.self, from: JSONEncoder().encode(m)) == m)
}

// Swift only: the snap panel sits centered above the cursor, drops below it at the top of the display,
// stays on the display, and hit finds the target under the cursor.
@Test func testSnapPanelLayout() {
    let (panel, cells) = SnapPanel.layout(3, at: SnapPoint(960, 500), screen: snapScreen)
    #expect(panel == F(850, 392, 220, 60))
    #expect(cells == [F(858, 400, 64, 44), F(928, 400, 64, 44), F(998, 400, 64, 44)])
    #expect(SnapPanel.hit(SnapPoint(940, 420), cells) == 1)
    #expect(SnapPanel.hit(SnapPoint(925, 420), cells) == nil)
    #expect(SnapPanel.hit(SnapPoint(940, 500), cells) == nil)
    let top = SnapPanel.layout(3, at: SnapPoint(960, 50), screen: snapScreen).panel
    #expect(top.y == 98)
    let corner = SnapPanel.layout(6, at: SnapPoint(10, 1075), screen: snapScreen).panel
    #expect(corner.x == 0 && corner.y == 1075 - 48 - 60)
    let right = SnapPanel.layout(6, at: SnapPoint(1915, 500), screen: snapScreen).panel
    #expect(right.x + right.w == 1920)
    #expect(SnapPanel.layout(0, at: SnapPoint(960, 500), screen: snapScreen).cells.isEmpty)
}
