import Testing

@testable import MooringsCore

// WidthsCase is one width resolution expectation.
struct WidthsCase: Sendable, CustomTestStringConvertible {
    // Saved is the saved choice.
    let saved: Widths?
    // Config is the configured pair.
    let config: Widths?
    // WantWidths is the expected pair in effect.
    let wantWidths: Widths
    // WantWarning reports whether a fallback warning is expected.
    let wantWarning: Bool

    // testDescription labels the case in test output.
    var testDescription: String { "saved \(String(describing: saved)) config \(String(describing: config))" }
}

// widthsCases mirrors anchors_test.lua tests 26 and 63.
let widthsCases: [WidthsCase] = [
    WidthsCase(saved: nil, config: Widths(left: 10, right: 45), wantWidths: Widths(left: 10, right: 45), wantWarning: false), // Test 0: Config.
    WidthsCase(saved: Widths(left: 15, right: 30), config: Widths(left: 10, right: 45), wantWidths: Widths(left: 15, right: 30), wantWarning: false), // Test 1: Saved wins.
    WidthsCase(saved: nil, config: Widths(left: 50, right: 45), wantWidths: Widths(left: 10, right: 45), wantWarning: true), // Test 2: No channel.
    WidthsCase(saved: Widths(left: 60, right: 45), config: Widths(left: 10, right: 45), wantWidths: Widths(left: 10, right: 45), wantWarning: false), // Test 3: Bad saved.
    WidthsCase(saved: Widths(left: 45, right: 45), config: nil, wantWidths: Widths(left: 45, right: 45), wantWarning: false), // Test 4: Channel at 10.
    WidthsCase(saved: Widths(left: 0, right: 45), config: nil, wantWidths: Widths(left: 10, right: 45), wantWarning: true), // Test 5: Zero strip.
]

// testWidths checks which width pair wins.
@Test(arguments: widthsCases)
func testWidths(test: WidthsCase) {
    let (got, warning) = Layout.widths(saved: test.saved, config: test.config)
    #expect(got == test.wantWidths)
    #expect((warning != nil) == test.wantWarning)
}

// Test 6: Every preset leaves a usable channel.
@Test func testPresetsValid() {
    for preset in Layout.presets {
        #expect(Layout.validSplit(preset), "\(preset)")
    }
}

// SteppedCase is one width stepper expectation.
struct SteppedCase: Sendable, CustomTestStringConvertible {
    // Start is the pair before the step.
    let start: Widths
    // Side is the side stepped.
    let side: Side
    // Delta is the step.
    let delta: Double
    // MinPoints is the learned minimum width of the side's pin.
    let minPoints: Double
    // WantWidths is the expected pair after the step.
    let wantWidths: Widths
    // WantOK reports whether the step is allowed.
    let wantOK: Bool

    // testDescription labels the case in test output.
    var testDescription: String { "\(side) \(delta) from \(start)" }
}

// steppedCases mirrors anchors_test.lua tests 58, 60, 61 and 168.
let steppedCases: [SteppedCase] = [
    SteppedCase(start: Widths(left: 10, right: 45), side: .left, delta: 1, minPoints: 0, wantWidths: Widths(left: 11, right: 45), wantOK: true), // Test 0: Left wider.
    SteppedCase(start: Widths(left: 10, right: 45), side: .right, delta: -1, minPoints: 0, wantWidths: Widths(left: 10, right: 44), wantOK: true), // Test 1: Right narrower.
    SteppedCase(start: Widths(left: 45, right: 45), side: .left, delta: 1, minPoints: 0, wantWidths: Widths(left: 46, right: 45), wantOK: false), // Test 2: Channel floor.
    SteppedCase(start: Widths(left: 45, right: 45), side: .left, delta: -1, minPoints: 0, wantWidths: Widths(left: 44, right: 45), wantOK: true), // Test 3: Narrower allowed.
    SteppedCase(start: Widths(left: 1, right: 45), side: .left, delta: -1, minPoints: 0, wantWidths: Widths(left: 0, right: 45), wantOK: false), // Test 4: Strip at zero.
    SteppedCase(start: Widths(left: 10, right: 45), side: .left, delta: -1, minPoints: 500, wantWidths: Widths(left: 9, right: 45), wantOK: false), // Test 5: Held open.
    SteppedCase(start: Widths(left: 10, right: 45), side: .left, delta: 1, minPoints: 600, wantWidths: Widths(left: 11, right: 45), wantOK: true), // Test 6: Wider past a hold.
]

// testStepped checks the width steppers on the 5120 point ultrawide.
@Test(arguments: steppedCases)
func testStepped(test: SteppedCase) {
    let (got, ok) = Layout.stepped(test.start, test.side, test.delta, minPoints: test.minPoints, screenWidth: 5120)
    #expect(got == test.wantWidths)
    #expect(ok == test.wantOK)
}

// HeightsCase is one height resolution expectation.
struct HeightsCase: Sendable, CustomTestStringConvertible {
    // Saved is the saved choice.
    let saved: PartialHeights
    // Config is the configured pair.
    let config: PartialHeights
    // WantHeights is the expected pair in effect.
    let wantHeights: Heights
    // WantWarnings is the expected warning count.
    let wantWarnings: Int

    // testDescription labels the case in test output.
    var testDescription: String { "saved \(saved) config \(config)" }
}

// heightsCases mirrors anchors_test.lua tests 153, 156 and 157.
let heightsCases: [HeightsCase] = [
    HeightsCase(saved: PartialHeights(), config: PartialHeights(), wantHeights: Heights(left: 50, right: 50), wantWarnings: 0), // Test 0: Even.
    HeightsCase(saved: PartialHeights(), config: PartialHeights(left: 25, right: 95), wantHeights: Heights(left: 25, right: 50), wantWarnings: 1), // Test 1: Bad right.
    HeightsCase(saved: PartialHeights(left: 75), config: PartialHeights(left: 25), wantHeights: Heights(left: 75, right: 50), wantWarnings: 0), // Test 2: Choice wins.
    HeightsCase(saved: PartialHeights(left: 20), config: PartialHeights(right: 30), wantHeights: Heights(left: 20, right: 30), wantWarnings: 0), // Test 3: Partial.
    HeightsCase(saved: PartialHeights(left: 5), config: PartialHeights(right: 30), wantHeights: Heights(left: 50, right: 30), wantWarnings: 0), // Test 4: Bad saved.
]

// testHeights checks which top row heights win, side by side.
@Test(arguments: heightsCases)
func testHeights(test: HeightsCase) {
    let (got, warnings) = Layout.heights(saved: test.saved, config: test.config)
    #expect(got == test.wantHeights)
    #expect(warnings.count == test.wantWarnings)
}

// Test 5: A junk configured height, set but not a number, warns and falls back to 50.
@Test func testHeightsJunkConfig() {
    let (got, warnings) = Layout.heights(saved: PartialHeights(), config: PartialHeights(), configSet: [.left])
    #expect(got == Heights(left: 50, right: 50))
    #expect(warnings == ["leftTopPct must be a number from 10 to 90: using 50"])
}

// Test 6: The height steppers move by five and stop with either row at 10, mirroring test 155.
@Test func testTopStepped() {
    #expect(Layout.topStepped(Heights(left: 50, right: 50), .left, Layout.heightStep) == (55, true))
    #expect(Layout.topStepped(Heights(left: 90, right: 10), .left, 5) == (95, false))
    #expect(Layout.topStepped(Heights(left: 90, right: 10), .right, -5) == (5, false))
    #expect(Layout.topStepped(Heights(left: 90, right: 10), .right, 5) == (15, true))
}

// UltrawideCase is one screen choice expectation.
struct UltrawideCase: Sendable, CustomTestStringConvertible {
    // Screens are the full frames.
    let screens: [Frame]
    // WantIndex is the expected ultrawide, nil for none.
    let wantIndex: Int?

    // testDescription labels the case in test output.
    var testDescription: String { "\(screens)" }
}

// ultrawideCases mirrors anchors_test.lua test 27 and the screens seen in the step 0 spike.
let ultrawideCases: [UltrawideCase] = [
    UltrawideCase(screens: [F(0, 0, 3440, 1440), F(3440, 0, 5120, 1440)], wantIndex: 1), // Test 0: Widest wins.
    UltrawideCase(screens: [F(0, 0, 5120, 1440), F(5120, -1021, 1920, 1080)], wantIndex: 0), // Test 1: This desk.
    UltrawideCase(screens: [F(0, 0, 1512, 982)], wantIndex: nil), // Test 2: Laptop only.
    UltrawideCase(screens: [], wantIndex: nil), // Test 3: No screens.
]

// testUltrawide checks which screen counts as the ultrawide.
@Test(arguments: ultrawideCases)
func testUltrawide(test: UltrawideCase) {
    #expect(Layout.ultrawide(test.screens) == test.wantIndex)
}

// MenuBarCase is one menu bar inset expectation.
struct MenuBarCase: Sendable, CustomTestStringConvertible {
    // Usable are the usable frames the system reports.
    let usable: [Frame]
    // Full are the full frames.
    let full: [Frame]
    // Bars are the on-screen menu bar window bounds.
    let bars: [Frame]
    // WantUsable is the expected usable list.
    let wantUsable: [Frame]

    // testDescription labels the case in test output.
    var testDescription: String { "usable \(usable) bars \(bars)" }
}

// menuBarCases uses this desk: the C49 at the origin and the ARZOPA to its right and lower.
let menuBarCases: [MenuBarCase] = [
    MenuBarCase( // Test 0: ARZOPA reports no menu bar but shows one.
        usable: [F(0, 30, 5120, 1410), F(5120, 1381, 1920, 1080)],
        full: [F(0, 0, 5120, 1440), F(5120, 1381, 1920, 1080)],
        bars: [F(5120, 1381, 1920, 30), F(0, 0, 5120, 30)],
        wantUsable: [F(0, 30, 5120, 1410), F(5120, 1411, 1920, 1050)]),
    MenuBarCase( // Test 1: Usable already below the bar.
        usable: [F(0, 30, 5120, 1410)], full: [F(0, 0, 5120, 1440)], bars: [F(0, 0, 5120, 30)],
        wantUsable: [F(0, 30, 5120, 1410)]),
    MenuBarCase( // Test 2: No bar on screen, as with an auto-hidden menu bar.
        usable: [F(5120, 1381, 1920, 1080)], full: [F(5120, 1381, 1920, 1080)], bars: [],
        wantUsable: [F(5120, 1381, 1920, 1080)]),
    MenuBarCase( // Test 3: A bar on another screen does not count.
        usable: [F(5120, 1381, 1920, 1080)], full: [F(5120, 1381, 1920, 1080)], bars: [F(0, 0, 5120, 30)],
        wantUsable: [F(5120, 1381, 1920, 1080)]),
    MenuBarCase( // Test 4: A bar below the top edge does not count.
        usable: [F(5120, 1381, 1920, 1080)], full: [F(5120, 1381, 1920, 1080)], bars: [F(5120, 1400, 1920, 30)],
        wantUsable: [F(5120, 1381, 1920, 1080)]),
    MenuBarCase( // Test 5: A window too tall to be a menu bar does not count.
        usable: [F(5120, 1381, 1920, 1080)], full: [F(5120, 1381, 1920, 1080)], bars: [F(5120, 1381, 1920, 600)],
        wantUsable: [F(5120, 1381, 1920, 1080)]),
    MenuBarCase( // Test 6: No screens.
        usable: [], full: [], bars: [F(0, 0, 5120, 30)], wantUsable: []),
]

// testBelowMenuBars checks the usable frames are moved below a menu bar the system left out.
@Test(arguments: menuBarCases)
func testBelowMenuBars(test: MenuBarCase) {
    #expect(Layout.belowMenuBars(usable: test.usable, full: test.full, bars: test.bars) == test.wantUsable)
}
